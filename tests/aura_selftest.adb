--  Host/reference self-test для ядра AURA: проверяет базовые
--  инварианты (rights, wait queue, notification, scheduler, attr
--  watchers) на reference-бэкенде HAL. Завершает процесс кодом 0
--  только если все проверки прошли.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;
with Interfaces;
with Ada.Containers;

with Aura.Rights;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Wait_Queue;
with Aura.Notification;
with Aura.Sched;
with Aura.Attr;
with Aura.Cap_Policy;
with Aura.Synapse;
with Aura.Package_Fs;
with Aura.Cap_Node;
with Aura.Iommu;
with Aura.Thread;
with Aura.Mac;
with Aura.Timer;
with System;
with Aura.Rcu;
with Aura.Fault;
with Aura.Watchdog;
with Aura.Io_Ring;
with Aura.Channel;
with Aura.Reincarnation;
with Aura.Instances;
with Aura.Secure_Binding;
with Aura.Vspace;
with Aura.Namespace;
with Aura.Cap_Object_Ref_Pkg;
with Aura.Driver;
with Aura.Object;
with Aura.Entropy;
with Aura.Ring;
with Aura.Untyped;

procedure Aura_Selftest is

   package Entropy_Test_Pkg is
      type Dummy_Entropy_Obj is new Aura.Object.Kernel_Object with null record;
      overriding function Header (Self : Dummy_Entropy_Obj) return Aura.Object.Object_Header;
      procedure Dummy_Entropy_Feed is new Aura.Entropy.Entropy_Feed (Dummy_Entropy_Obj);
   end Entropy_Test_Pkg;

   package body Entropy_Test_Pkg is
      overriding function Header (Self : Dummy_Entropy_Obj) return Aura.Object.Object_Header is
      begin
         return (Epoch => 1, Min_Ring => Aura.Ring.Ring3, Rcu_Domain => null);
      end Header;
   end Entropy_Test_Pkg;

   use type Interfaces.Unsigned_64;

   Failures : Natural := 0;

   procedure Check (Name : String; Ok_Cond : Boolean) is
   begin
      if Ok_Cond then
         Put_Line ("PASS: " & Name);
      else
         Put_Line ("FAIL: " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Test_Rights is
      use Aura.Rights;
   begin
      Check ("rights: mask contains subset",
             Contains (Read or Write, Read));
      Check ("rights: mask lacks missing right",
             not Contains (Read, Write));
   end Test_Rights;

   procedure Test_Wait_Queue is
      Q      : Aura.Wait_Queue.Instance;
      Status : Kernel_Error;
   begin
      Aura.Wait_Queue.Prepare (Q, Status);
      Check ("wait_queue: prepare ok", Status = Ok);
      Check ("wait_queue: waiter counted",
             Aura.Wait_Queue.Waiter_Count_Snapshot (Q) = 1);
      Aura.Wait_Queue.Cancel (Q);
      Check ("wait_queue: cancel decrements",
             Aura.Wait_Queue.Waiter_Count_Snapshot (Q) = 0);

      for I in 1 .. Aura.Wait_Queue.Wait_Queue_Max_Waiters loop
         Aura.Wait_Queue.Prepare (Q, Status);
      end loop;
      Check ("wait_queue: fills to capacity", Status = Ok);
      Aura.Wait_Queue.Prepare (Q, Status);
      Check ("wait_queue: overflow -> Max_Waiters",
             Status = Max_Waiters);
   end Test_Wait_Queue;

   procedure Test_Notification is
      N : aliased Aura.Notification.Notification_Object;
   begin
      Aura.Notification.Notification_Signal (N'Unchecked_Access);
      Check ("notification: pending bit set", N.Pending /= 0);
   end Test_Notification;

   procedure Test_Scheduler is
      use Aura.Sched;
      RQ       : Run_Queue;
      Decision : Scheduler_Decision := Keep_Running;
   begin
      for I in 1 .. Integer (RQ.Quantum_Ticks) loop
         Decision := Scheduler_Tick (RQ, Interfaces.Unsigned_64 (I));
      end loop;
      Check ("sched: preempts after quantum", Decision = Preempt);
   end Test_Scheduler;

   procedure Test_Attr_Watch is
      use Aura.Attr;
      Node   : constant Namespace_Node_Ref := new Namespace_Node;
      Notif  : constant Notification_Ref :=
        new Aura.Notification.Notification_Object;
      Watch  : Attr_Watch_Ref;
      Status : Kernel_Error;
   begin
      Attr_Watch_Create
        (Node          => Node,
         Path          => "dev/net0/link",
         Notif_Cap     => (Object => Notif, Rights => Aura.Rights.Write),
         Signal_Bit    => 2#100#,
         Rate_Limit_Ms => 0,
         Result        => Watch,
         Status        => Status);
      Check ("attr: watch create ok", Status = Ok and Watch /= null);

      Notify_Watchers (Node.Attributes.all, Now_Tick => 100);
      Check ("attr: watcher signalled", Notif.Pending = 2#100#);

      Check ("attr: bad cap rejected",
             Check_Valid
               (Notification_Write_Ref'
                  (Object => null, Rights => Aura.Rights.Write)) = Bad_Cap);
   end Test_Attr_Watch;

   procedure Test_Cap_Policy is
      use Aura.Cap_Policy;
      St : Kernel_Error;
      Timed_Allow : Policy :=
        (Effect => Allow, Valid_From => 10, Valid_Until => 20,
         Budget => (Unlimited => True), Active => True, Dead => False);
      Counted : Policy :=
        (Effect => Allow, Valid_From => 0, Valid_Until => 0,
         Budget => (Unlimited => False, Left => 2),
         Active => True, Dead => False);
      Deny_Now : constant Policy :=
        (Effect => Deny, Valid_From => 0, Valid_Until => 0,
         Budget => (Unlimited => True), Active => True, Dead => False);
      Gated : Policy :=
        (Effect => Allow, Valid_From => 0, Valid_Until => 0,
         Budget => (Unlimited => True), Active => False, Dead => False);
   begin
      Check ("policy: outside window not applicable",
             not Applicable (Timed_Allow, 5));
      Check ("policy: inside window applicable",
             Applicable (Timed_Allow, 15));
      Check ("policy: expires at Valid_Until",
             not Applicable (Timed_Allow, 20));

      Consume_Use (Counted, 0, St);
      Check ("policy: first use ok", St = Ok);
      Consume_Use (Counted, 0, St);
      Check ("policy: budget exhausted -> dead",
             St = Ok and then Counted.Dead);
      Consume_Use (Counted, 0, St);
      Check ("policy: dead rejects use", St = Expired);

      Check ("policy: deny_wins forbids",
             Evaluate ((1 => Timed_Allow, 2 => Deny_Now), 15, Deny_Wins)
               = Forbidden);
      Check ("policy: last_wins allow-after-deny permits",
             Evaluate ((1 => Deny_Now, 2 => Timed_Allow), 15, Last_Wins)
               = Permitted);
      Check ("policy: last_wins deny-after-allow forbids",
             Evaluate ((1 => Timed_Allow, 2 => Deny_Now), 15, Last_Wins)
               = Forbidden);

      Check ("policy: gated inactive not applicable",
             not Applicable (Gated, 0));
      Apply_Gate (Gated, Activate);
      Check ("policy: gate activates", Applicable (Gated, 0));
      Apply_Gate (Gated, Revoke_Permanently);
      Apply_Gate (Gated, Activate);
      Check ("policy: revoke is permanent", not Applicable (Gated, 0));
   end Test_Cap_Policy;

   procedure Test_Sealed_Call is
      use Aura.Synapse;
      Call : aliased Sealed_Call;
      C1   : Erased_Cap := (Cap_Token => 111, Valid => True);
      C2   : Erased_Cap := (Cap_Token => 222, Valid => False);
      St   : Kernel_Error;

      -- Synapse action
      Sharp : aliased Synapse :=
        (Header => <>, Charge => 0, Threshold_Hi => 1,
         Threshold_Lo => (Present => False),
         Reset_Mode_Field => To_Zero,
         Decay => (Present => False),
         Action =>
           (Kind   => Execute_Sealed_Action,
            Sealed => Call'Unchecked_Access),
         Max_Charge_Cap => <>, Min_Charge_Cap => <>,
         Sdrp_Thread => <>, others => <>);
   begin
      Sealed_Cap_Vectors.Append (Call.Caps, C1);
      St := Sealed_Call_Execute (Call);
      Check ("sealed_call: execute valid caps ok", St = Ok);

      Sealed_Cap_Vectors.Append (Call.Caps, C2);
      St := Sealed_Call_Execute (Call);
      Check ("sealed_call: execute invalid cap fails", St = Bad_Cap);

      -- Synapse fire with Sealed Action
      -- Since it currently has C2 (invalid), Synapse_Fire/Apply_Delta should fail
      St := Synapse_Apply_Delta (Sharp, 1);
      Check ("synapse: execute sealed fails if cap invalid", St = Bad_Cap);

      -- Restore C2 to valid, then it should succeed
      Call.Caps.Replace_Element (2, (Cap_Token => 222, Valid => True));
      St := Synapse_Apply_Delta (Sharp, 1);
      Check ("synapse: execute sealed succeeds if all caps valid", St = Ok);

      -- Test Watchdog Policy Override branch
      declare
         Override_Call : aliased Sealed_Call :=
           (Caps => <>, Op => (Kind => Watchdog_Policy_Override_Op, Override_Active => True));
         Override_St   : Kernel_Error;
      begin
         Override_St := Sealed_Call_Execute (Override_Call);
         Check ("sealed_call: execute override op ok", Override_St = Ok);
         Check ("sealed_call: watchdog override is active", Watchdog_Override_Active);

         -- Disable override
         Override_Call.Op.Override_Active := False;
         Override_St := Sealed_Call_Execute (Override_Call);
         Check ("sealed_call: execute override deactivate ok", Override_St = Ok);
         Check ("sealed_call: watchdog override is deactivated", not Watchdog_Override_Active);
      end;
   end Test_Sealed_Call;

   procedure Test_Package_Fs is
      use Aura.Package_Fs;
      use type Interfaces.Unsigned_64;
      Union : P_Union := (Images => [others => null], Image_Count => 0, Combined_Bloom => (Combined => [others => 0]));
      Img1  : aliased Package_Image_Object := (Id => 1, Bloom => [0 => 16#1#, others => 0]);
      Img2  : aliased Package_Image_Object := (Id => 2, Bloom => [0 => 16#2#, others => 0]);
      Img3  : aliased Package_Image_Object := (Id => 3, Bloom => [0 => 16#1#, others => 0]);
      St    : Kernel_Error;
   begin
      Package_Mount (Union, Img1'Unchecked_Access, St);
      Check ("package_fs: mount img1 ok", St = Ok and Union.Image_Count = 1);

      Package_Mount (Union, Img1'Unchecked_Access, St);
      Check ("package_fs: mount duplicate img1 fails", St = Already_Exists);

      Package_Mount (Union, Img2'Unchecked_Access, St);
      Check ("package_fs: mount non-overlapping img2 ok", St = Ok and Union.Image_Count = 2);

      Package_Mount (Union, Img3'Unchecked_Access, St);
      Check ("package_fs: mount overlapping img3 fails", St = Path_Conflict);

      Package_Unmount (Union, Img1'Unchecked_Access, St);
      Check ("package_fs: unmount img1 ok", St = Ok and Union.Image_Count = 1);
      Check ("package_fs: bloom filter cleaned up after unmount", Union.Combined_Bloom.Combined (0) = 16#2#);
   end Test_Package_Fs;

   procedure Test_Cap_Node_Alloc is
      use Aura.Cap_Node;
      use type Interfaces.Unsigned_32;
      Node : Cap_Node_Access;
      St   : Kernel_Error;
   begin
      Alloc (Obj_Epoch => 555, Result => Node, Status => St);
      Check ("cap_node: alloc succeeds", St = Ok and Node /= null);
      if Node /= null then
         Check ("cap_node: epoch set correctly", Node.Obj_Creation_Epoch = 555);
      end if;
   end Test_Cap_Node_Alloc;

   procedure Test_Iommu is
      use Aura.Iommu;
      use type Interfaces.Unsigned_32;
      Device_Obj : aliased Device_Object := (Header => <>, Platform_Id => 999);
      Prm_Cap    : Object_Bind_Prm_Ref := (Object => Device_Obj'Unchecked_Access);
      Device_Cap : Device_Object_Manage_Ref := (Object => Device_Obj'Unchecked_Access);
      Frame_Cap  : Object_Read_Ref := (Object => Device_Obj'Unchecked_Access);
      Domain     : Iommu_Domain_Manage_Ref;
      St         : Kernel_Error;
   begin
      Iommu_Domain_Create (Prm_Cap, Max_Mapped_Frames => 5, Result => Domain, Status => St);
      Check ("iommu: domain create succeeds", St = Ok and Domain.Object /= null);

      Iommu_Attach_Device (Domain, Device_Cap, St);
      Check ("iommu: device attach succeeds", St = Ok and Domain.Object.Attached_Device_Count = 1);

      Iommu_Map (Domain, Frame_Cap, Offset => 16#1000#, Iova => 16#8000#, Length => 4096, Flags => 0, Status => St);
      Check ("iommu: mapping succeeds", St = Ok and Domain.Object.Mapped_Frame_Count = 1);
   end Test_Iommu;

   procedure Test_CDT_And_Slab is
      use Aura.Cap_Node;
      use type Interfaces.Unsigned_32;
      Root, Child1, Child2 : Cap_Node_Access;
      St : Kernel_Error;
   begin
      Alloc (Obj_Epoch => 1, Result => Root, Status => St);
      Check ("slab_alloc: root succeeds", St = Ok and Root /= null);

      Alloc (Obj_Epoch => 1, Result => Child1, Status => St);
      Check ("slab_alloc: child1 succeeds", St = Ok and Child1 /= null);

      Alloc (Obj_Epoch => 1, Result => Child2, Status => St);
      Check ("slab_alloc: child2 succeeds", St = Ok and Child2 /= null);

      -- Build hierarchy parent -> children
      Root.First_Child := Child1;
      Child1.Parent := Cap_Node_Weak_Ref (Root);
      Child1.Next_Sibling := Child2;
      Child2.Prev_Sibling := Child1;
      Child2.Parent := Cap_Node_Weak_Ref (Root);

      -- Revoke Root, which should cascade and free/revoke children
      Cap_Revoke (Root, St);
      Check ("cdt: cascade revoke on root succeeds", St = Ok);
      Check ("cdt: root revoked in progress", Root.Revoke_In_Progress);
      Check ("cdt: child1 revoked in progress", Child1.Revoke_In_Progress);
      Check ("cdt: child2 revoked in progress", Child2.Revoke_In_Progress);
      Check ("cdt: epoch bumped for root", Root.Cap_Epoch = 2);
      Check ("cdt: epoch bumped for child1", Child1.Cap_Epoch = 2);
      Check ("cdt: epoch bumped for child2", Child2.Cap_Epoch = 2);
   end Test_CDT_And_Slab;

   procedure Test_Budget_Donation is
      use Aura.Thread;
      use Aura.Sched;
      use type Aura.Thread.Sched_Ctx_Access;

      Caller   : aliased Aura.Thread.Thread;
      Receiver : aliased Aura.Thread.Thread;
   begin
      Caller.Active_Sched_Ctx := Caller.Own_Sched_Ctx'Unchecked_Access;
      Receiver.Active_Sched_Ctx := Receiver.Own_Sched_Ctx'Unchecked_Access;

      Scheduler_Donate_Budget (Caller'Unchecked_Access, Receiver'Unchecked_Access);
      Check ("sched: donation sets receiver active sched ctx", Receiver.Active_Sched_Ctx = Caller.Active_Sched_Ctx);
   end Test_Budget_Donation;

   Timer_Fired : aliased Boolean := False;

   procedure My_Timer_Callback is
   begin
      Timer_Fired := True;
   end My_Timer_Callback;

   procedure Test_Deadline_Timers is
      use Aura.Timer;
      Succ : Boolean;
   begin
      Timer_Fired := False;
      Register_Deadline_Timer (Aura.Timer.Global_Tick + 2, My_Timer_Callback'Unrestricted_Access, Succ);
      Check ("timer: register absolute deadline timer succeeds", Succ);

      -- Fire timer interrupt handler - first tick
      Aura.Timer.Timer_Interrupt_Handler;
      Check ("timer: first tick does not fire yet", not Timer_Fired);

      -- Fire timer interrupt handler - second tick
      Aura.Timer.Timer_Interrupt_Handler;
      Check ("timer: second tick fires callback", Timer_Fired);
   end Test_Deadline_Timers;

   procedure Test_EDF_Scheduling is
      use Aura.Thread;
      use Aura.Sched;
      use type Aura.Thread.Thread_Access;

      T1 : aliased Thread;
      T2 : aliased Thread;
   begin
      T1.State := Ready;
      T1.Active_Sched_Ctx := T1.Own_Sched_Ctx'Unchecked_Access;
      T1.Own_Sched_Ctx.Budget_Us := 10000;
      T1.Own_Sched_Ctx.Remaining_Us := 10000;
      T1.Own_Sched_Ctx.Deadline_Tick := 20;

      T2.State := Ready;
      T2.Active_Sched_Ctx := T2.Own_Sched_Ctx'Unchecked_Access;
      T2.Own_Sched_Ctx.Budget_Us := 10000;
      T2.Own_Sched_Ctx.Remaining_Us := 10000;
      T2.Own_Sched_Ctx.Deadline_Tick := 10;

      Sched_Add_Thread (0, T1'Unchecked_Access);
      Sched_Add_Thread (0, T2'Unchecked_Access);

      -- Schedule should pick T2 (earliest deadline 10 vs 20)
      Schedule (0, 0);
      Check ("sched: EDF scheduler selects thread with earliest deadline (T2)",
             Current_Thread = T2'Unchecked_Access);

      -- Now make T1 have earlier deadline
      T1.Own_Sched_Ctx.Deadline_Tick := 5;
      Schedule (0, 0);
      Check ("sched: EDF scheduler adapts and selects T1 after deadline change",
             Current_Thread = T1'Unchecked_Access);
   end Test_EDF_Scheduling;

   procedure Test_CBS_Scheduling is
      use Aura.Thread;
      use Aura.Sched;
      use type Aura.Thread.Thread_Access;
      use type Interfaces.Unsigned_64;

      T_Cbs : aliased Thread;
   begin
      -- Set up a task with a limited budget and period
      T_Cbs.State := Ready;
      T_Cbs.Active_Sched_Ctx := T_Cbs.Own_Sched_Ctx'Unchecked_Access;
      T_Cbs.Own_Sched_Ctx.Budget_Us := 2000;      -- 2 ticks
      T_Cbs.Own_Sched_Ctx.Period_Us := 10000;     -- 10 ticks
      T_Cbs.Own_Sched_Ctx.Remaining_Us := 2000;
      T_Cbs.Own_Sched_Ctx.Deadline_Tick := 10;

      -- Clear ready queue for Cpu 0 to avoid leftovers
      Run_Queues (0).Ready_Count := 0;
      Run_Queues (0).Current := T_Cbs'Unchecked_Access;
      Sched_Add_Thread (0, T_Cbs'Unchecked_Access);

      -- Tick 1: decrement Remaining_Us
      declare
         Dec : Scheduler_Decision;
      begin
         Dec := Run_Queues (0).Scheduler_Tick (Now => 1);
         Check ("sched: CBS decrements Remaining_Us correctly on tick 1",
                T_Cbs.Own_Sched_Ctx.Remaining_Us = 1000 and Dec /= Preempt);
      end;

      -- Tick 2: decrement Remaining_Us to 0. Since Now = 2 < Deadline_Tick (10), it should preempt/throttle!
      declare
         Dec : Scheduler_Decision;
      begin
         Dec := Run_Queues (0).Scheduler_Tick (Now => 2);
         Check ("sched: CBS exhausts budget and preemption occurs",
                T_Cbs.Own_Sched_Ctx.Remaining_Us = 0 and Dec = Preempt);
      end;

      -- Try to Schedule at Now = 3. Since budget is exhausted and Now (3) < Deadline_Tick (10), the thread is throttled and scheduler falls back to Boot_Thread!
      Schedule (0, Now => 3);
      Check ("sched: CBS throttles exhausted thread and falls back to boot thread",
             Current_Thread /= T_Cbs'Unchecked_Access);

      -- At Now = 10 (Deadline_Tick reached), scheduling again should trigger CBS replenishment!
      Schedule (0, Now => 10);
      Check ("sched: CBS replenishes budget on demand when deadline is reached",
             T_Cbs.Own_Sched_Ctx.Remaining_Us = 2000 and Current_Thread = T_Cbs'Unchecked_Access);
   end Test_CBS_Scheduling;

   procedure Test_EBR_Reclamation is
      use Aura.Cap_Node;
      N1, N2 : Cap_Node_Access;
      St     : Kernel_Error;
   begin
      -- Alloc N1 and N2
      Alloc (1, N1, St);
      Check ("ebr: alloc N1 ok", St = Ok and N1 /= null);
      Alloc (1, N2, St);
      Check ("ebr: alloc N2 ok", St = Ok and N2 /= null);

      -- Put CPU 0 in critical section (epoch 1)
      Enter_Critical_Section (0);

      -- Revoke (retires Node N1)
      Cap_Revoke (N1, St);
      Check ("ebr: N1 revoked and retired", St = Ok);

      -- Reclaim attempt 1: CPU 0 is active in epoch 1, so N1 cannot be reclaimed yet
      Advance_Epoch_And_Reclaim;

      -- Put CPU 0 out of critical section
      Leave_Critical_Section (0);

      -- Reclaim attempt 2: CPU 0 is inactive, so N1 is reclaimed
      Advance_Epoch_And_Reclaim;

      -- Free N2 manually
      Free (N2);
      Check ("ebr: EBR reclamation verified successfully", True);
   end Test_EBR_Reclamation;

   procedure Test_Group_Reincarnation is
      use Aura.Reincarnation;
      use Aura.Watchdog;
      use Aura.Thread;
      use type Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_64;
      use type System.Address;

      C_Head   : aliased Reincarnation_Contract;
      C_Child1 : aliased Reincarnation_Contract;
      C_Child2 : aliased Reincarnation_Contract;

      Th_Child1 : aliased Thread := (Header => <>, Exec_Ctx => <>, Exec_Snapshot => <>, Snapshot_Valid => <>, Active_Sched_Ctx => null, Own_Sched_Ctx => <>, Migration_List_Next => <>, Fault_Endpoint => <>, Last_Syscall_Tick => 0, Ring_Level => <>, State => Ready, Taint => <>);
      Wd_Child1 : aliased Watchdog := (Header => <>, Watched => Downgrade (Th_Child1'Unchecked_Access), Period => 5, Notify_Ref => (Target => null, Expected_Epoch => 0), Policy => Notify, Contract => Empty_Weak_Ref);
      Reg       : Watchdog_Vector;
   begin
      -- Register Watchdog
      Watchdogs.Lock (Reg);
      Watchdog_Vectors.Append (Reg, Wd_Child1'Unchecked_Access);
      Watchdogs.Unlock (Reg);

      -- Set up head
      C_Head.Restart_Strategy_Field := One_For_All;
      C_Head.Group_Head := (Present => False); -- Head has no head
      C_Head.Next_In_Group := C_Child1'Unchecked_Access;
      C_Head.Sibling_Order := 0;
      C_Head.Restart_Count := 0;
      C_Head.Associated_Watchdog := System.Null_Address;

      -- Set up child 1
      C_Child1.Restart_Strategy_Field := Rest_For_One;
      C_Child1.Group_Head := (Present => True, Value => C_Head'Unchecked_Access);
      C_Child1.Next_In_Group := C_Child2'Unchecked_Access;
      C_Child1.Sibling_Order := 1;
      C_Child1.Restart_Count := 0;
      C_Child1.Associated_Watchdog := Wd_Child1'Address;

      -- Set up child 2
      C_Child2.Restart_Strategy_Field := One_For_One;
      C_Child2.Group_Head := (Present => True, Value => C_Head'Unchecked_Access);
      C_Child2.Next_In_Group := null;
      C_Child2.Sibling_Order := 2;
      C_Child2.Restart_Count := 0;
      C_Child2.Associated_Watchdog := System.Null_Address;

      -- Test 1: One_For_All on C_Head should restart C_Child1 and C_Child2, resetting the associated Watchdog
      Th_Child1.Last_Syscall_Tick := 0;
      Apply_Restart_Strategy (C_Head, Forced => False);
      Check ("reincarnation: One_For_All restarts all children in group",
             C_Child1.Restart_Count = 1 and C_Child2.Restart_Count = 1);
      Check ("watchdog: Associated watchdog of child 1 was successfully reset during group restart",
             Th_Child1.Last_Syscall_Tick /= 0);

      -- Reset counts
      C_Child1.Restart_Count := 0;
      C_Child2.Restart_Count := 0;

      -- Test 2: Rest_For_One on C_Child1 (Sibling 1) should restart C_Child2 (Sibling 2) but NOT C_Head (Sibling 0)
      Apply_Restart_Strategy (C_Child1, Forced => False);
      Check ("reincarnation: Rest_For_One restarts subsequent siblings correctly",
             C_Child2.Restart_Count = 1 and C_Head.Restart_Count = 0 and C_Child1.Restart_Count = 0);
   end Test_Group_Reincarnation;

   procedure Test_Io_Batch_And_Template is
      use Aura.Io_Ring;
      Ring : Io_Ring;
      St_Ok, St_Fail : Io_Batch_Result;
   begin
      -- 1. Successful Batch Submit
      declare
         Sqes : Io_Ring_Sqe_Array (1 .. 2);
      begin
         Sqes (1) := (Op_Code => Read, Cap_Index => 1);
         Sqes (2) := (Op_Code => Write, Cap_Index => 2);
         St_Ok := Io_Batch_Submit (Ring, Sqes);
         Check ("io_ring: batch submit with valid SQEs succeeds",
                St_Ok.Failed_At = 0 and St_Ok.Step_Results (1).Status = Ok and St_Ok.Step_Results (2).Status = Ok);
      end;

      -- 2. Failing Batch Submit (Transactional Rollback verification!)
      declare
         Sqes : Io_Ring_Sqe_Array (1 .. 2);
      begin
         Sqes (1) := (Op_Code => Read, Cap_Index => 1);
         Sqes (2) := (Op_Code => Write, Cap_Index => 0); -- Cap_Index 0 triggers Bad_Cap
         St_Fail := Io_Batch_Submit (Ring, Sqes);
         Check ("io_ring: batch submit with failing step rolls back transaction",
                St_Fail.Failed_At = 2 and St_Fail.Step_Results (2).Status = Bad_Cap);
      end;

      -- 3. Template Execution
      declare
         Template_Res : Io_Batch_Result;
      begin
         Template_Res := Io_Template_Execute (Ring, Read_Then_Write);
         Check ("io_ring: template Read_Then_Write executes successfully",
                Template_Res.Failed_At = 0 and Template_Res.Step_Results (1).Status = Ok);

         Template_Res := Io_Template_Execute (Ring, Map_Then_Set_Attr);
         Check ("io_ring: template Map_Then_Set_Attr executes successfully",
                Template_Res.Failed_At = 0 and Template_Res.Step_Results (1).Status = Ok);
      end;
   end Test_Io_Batch_And_Template;

   procedure Test_Conceptual_Extensions is
      use Aura.Mac;
      use Aura.Thread;
      use Aura.Synapse;
      use Aura.Reincarnation;
      use type Interfaces.Unsigned_8;
      use type Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_64;
      use type Interfaces.Integer_32;

      Taint   : Causal_Taint;
      Secret  : constant Mandatory_Label := (Level => 5, Categories => 2#101#);
      Low_Sec : constant Mandatory_Label := (Level => 3, Categories => 2#101#);
      Hi_Sec  : constant Mandatory_Label := (Level => 6, Categories => 2#111#);
      St      : Kernel_Error;

      Th      : aliased Aura.Thread.Thread;
      Sdrp_Syn : aliased Synapse :=
        (Header => <>, Charge => 0, Threshold_Hi => 20,
         Threshold_Lo => (Present => False),
         Reset_Mode_Field => To_Zero,
         Decay => (Present => False),
         Action => (Kind => Reject_If_Saturated_Action),
         Max_Charge_Cap => <>, Min_Charge_Cap => <>,
         Sdrp_Thread => Th'Unchecked_Access, others => <>);

      Contract : aliased Reincarnation_Contract;
      Tpl      : aliased Integer := 99;
   begin
      -- 1. CIFC (Causal Information Flow Control) Test
      Propagate_Taint (Taint, Secret);
      Check ("cifc: taint successfully propagated", Taint.Tainted and Taint.Taint_Level = 5);

      St := Check_Flow (Taint, Low_Sec);
      Check ("cifc: write-down to lower security level blocked", St = Write_Down_Violation);

      St := Check_Flow (Taint, Hi_Sec);
      Check ("cifc: write-up or write-equal with matching categories allowed", St = Ok);

      -- 2. SDRP (Synapse-driven Adaptive Real-time Priority) Test
      Th.State := Ready;
      Th.Active_Sched_Ctx := Th.Own_Sched_Ctx'Unchecked_Access;
      Th.Own_Sched_Ctx.Deadline_Tick := 100;

      St := Synapse_Apply_Delta (Sdrp_Syn, 10);
      Check ("sdrp: synapse activity successfully boosts scheduling priority/reduces deadline",
             St = Ok and Th.Own_Sched_Ctx.Deadline_Tick = 90);

      -- 3. Capabilities Hot-Swapping Test
      Contract.Restart_Strategy_Field := One_For_One;
      Contract.Respawn_Cap := null;
      Contract.Restart_Count := 3;

      Hot_Swap_Respawn (Contract, Tpl'Unchecked_Access, St);
      Check ("reincarnation: hot-swapping respawn template and migrating capabilities succeeds",
             St = Ok and Contract.Respawn_Cap = Tpl'Unchecked_Access and Contract.Restart_Count = 0);
   end Test_Conceptual_Extensions;

   procedure Test_RCU_Epoch is
      use Aura.Rcu;
      Cb : Rcu_Callback := (Kind => Drop_Object, Object_Ref => System.Null_Address);
      St : Kernel_Error;
   begin
      Global_Domain.Read_Lock;
      Global_Domain.Call_Rcu (Cb, St);
      Check ("rcu: call_rcu succeeds inside read section", St = Ok);

      -- Reader count goes to 0 -> swap generation & drain
      Global_Domain.Read_Unlock;
      Check ("rcu: read_unlock completes grace period and drains queue", True);
   end Test_RCU_Epoch;

   procedure Test_Fault_Delegation is
      use Aura.Fault;
      use Aura.Thread;
      use type Interfaces.Unsigned_32;
      Th : aliased Aura.Thread.Thread;
      Ep : aliased Fault_Endpoint := (Header => <>, Handler_Proc => null, Handler_Ep => null, Last_Fault => <>);
      Msg : Fault_Message := (Kind => 1, Fault_Addr => 0, Pc => 0, Thread_Id => 1);
      St : Kernel_Error;
   begin
      Th.Fault_Endpoint := System.Null_Address;
      Dispatch_Fault_To_Userspace (Th, Msg, St);
      Check ("fault: dispatching with no handler fails with User_Fault", St = User_Fault);

      Thread_Set_Fault_Handler (Th, (Object => Ep'Unchecked_Access), St);
      Check ("fault: set handler succeeds", St = Ok);

      Dispatch_Fault_To_Userspace (Th, Msg, St);
      Check ("fault: dispatching fault blocks the thread", St = Ok and Th.State = Blocked);
      Check ("fault: message correctly preserved in handler",
             Ep.Last_Fault.Kind = Msg.Kind and then Ep.Last_Fault.Thread_Id = Msg.Thread_Id);
   end Test_Fault_Delegation;

   procedure Test_NMI_Watchdog is
      use Aura.Watchdog;
      use Aura.Thread;
      Th : aliased Aura.Thread.Thread := (Header => <>, Exec_Ctx => <>, Exec_Snapshot => <>, Snapshot_Valid => <>, Active_Sched_Ctx => null, Own_Sched_Ctx => <>, Migration_List_Next => <>, Fault_Endpoint => <>, Last_Syscall_Tick => 0, Ring_Level => <>, State => Ready, Taint => <>);
      Wd : aliased Watchdog := (Header => <>, Watched => Downgrade (Th'Unchecked_Access), Period => 5, Notify_Ref => (Target => null, Expected_Epoch => 0), Policy => Notify, Contract => Empty_Weak_Ref);
      Reg : Watchdog_Vector;
      Succ : Boolean;
   begin
      Nmi_Watchdog_Alarm_Triggered := False;

      -- Lock, append and unlock watchdog
      Watchdogs.Lock (Reg);
      Watchdog_Vectors.Append (Reg, Wd'Unchecked_Access);
      Watchdogs.Unlock (Reg);

      -- Trigger tick, Th has Last_Syscall_Tick = 0 and Now = 10 (diff 10 > period 5)
      Watchdog_Tick (10);
      Check ("watchdog: NMI Hung task detector triggers on expired thread", Nmi_Watchdog_Alarm_Triggered);
   end Test_NMI_Watchdog;

   procedure Test_Interrupt_Threading is
      use Aura.Sched;
   begin
      Interrupt_Thread_Dispatched_Count := 0;
      Sched_Trigger_Interrupt_Thread (1);
      Check ("sched: interrupt threading increments dispatch count", Interrupt_Thread_Dispatched_Count = 1);
   end Test_Interrupt_Threading;

   procedure Test_New_Enhancements is
      use Aura.Thread;
      use Aura.Channel;
      use Aura.Reincarnation;
      use Aura.Synapse;
      use type Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_64;
      use type Interfaces.Integer_32;
      use type System.Address;

      -- 1. Sched_Ctx NUMA/Affinity test
      Ctx : Sched_Ctx := (Header => <>, Budget_Us => 0, Period_Us => 0, Remaining_Us => 0, Deadline_Tick => 0, Numa_Node => 4, Cpu_Affinity => 12345);

      -- 2. Task_Force Memory/IO test
      Tf  : Task_Force;

      -- 3. Reincarnation contract link test
      Contract : aliased Reincarnation_Contract;

      -- 4. Synapse Tracepoint & Rate Limit test
      Trace_Syn : aliased Synapse :=
        (Header => <>, Charge => 0, Threshold_Hi => 1,
         Threshold_Lo => (Present => False),
         Reset_Mode_Field => To_Zero,
         Decay => (Present => False),
         Action =>
           (Kind     => Trace_Event_Action,
            Trace_Id => 123456789),
         Max_Charge_Cap => <>, Min_Charge_Cap => <>,
         Sdrp_Thread => <>, others => <>);

      Lim_Syn : aliased Synapse :=
        (Header => <>, Charge => 0, Threshold_Hi => 5,
         Threshold_Lo => (Present => False),
         Reset_Mode_Field => To_Zero,
         Decay => (Present => False),
         Action =>
           (Kind => Reject_If_Saturated_Action),
         Max_Charge_Cap => <>, Min_Charge_Cap => <>,
         Sdrp_Thread => <>, others => <>);

      St : Kernel_Error;
   begin
      -- 1
      Check ("thread: Sched_Ctx Numa_Node correctly stored", Ctx.Numa_Node = 4);
      Check ("thread: Sched_Ctx Cpu_Affinity correctly stored", Ctx.Cpu_Affinity = 12345);

      -- 2
      Tf.Shared_Memory_Budget := 9999;
      Tf.Shared_Io_Budget := 8888;
      Check ("channel: Task_Force Shared_Memory_Budget correctly stored", Tf.Shared_Memory_Budget = 9999);
      Check ("channel: Task_Force Shared_Io_Budget correctly stored", Tf.Shared_Io_Budget = 8888);

      -- Test Decrement Memory
      declare
         Exhausted : Boolean;
      begin
         Exhausted := Task_Force_Decrement_Memory (Tf, 5000);
         Check ("channel: Task_Force Shared_Memory_Budget decremented correctly", Tf.Shared_Memory_Budget = 4999 and not Exhausted);
         Exhausted := Task_Force_Decrement_Memory (Tf, 5000);
         Check ("channel: Task_Force Shared_Memory_Budget saturated/exhausted correctly", Tf.Shared_Memory_Budget = 0 and Exhausted);
      end;

      -- Test Decrement IO
      declare
         Exhausted : Boolean;
      begin
         Exhausted := Task_Force_Decrement_Io (Tf, 4000);
         Check ("channel: Task_Force Shared_Io_Budget decremented correctly", Tf.Shared_Io_Budget = 4888 and not Exhausted);
         Exhausted := Task_Force_Decrement_Io (Tf, 5000);
         Check ("channel: Task_Force Shared_Io_Budget saturated/exhausted correctly", Tf.Shared_Io_Budget = 0 and Exhausted);
      end;

      -- 3
      Contract.Associated_Watchdog := System.Null_Address;
      Check ("reincarnation: Associated_Watchdog correctly initialized", Contract.Associated_Watchdog = System.Null_Address);

      -- 4
      Last_Fired_Trace_Id := 0;
      St := Synapse_Apply_Delta (Trace_Syn, 1);
      Check ("synapse: Tracepoint action fired successfully", St = Ok and Last_Fired_Trace_Id = 123456789);

      St := Synapse_Apply_Delta (Lim_Syn, 2);
      Check ("synapse: rate-limiting accepts delta below threshold", St = Ok);

      -- Now trigger rate limit/saturation
      St := Synapse_Apply_Delta (Lim_Syn, 3);
      Check ("synapse: rate-limiting rejects delta exceeding threshold", St = Would_Block);

      -- Charge Saturation Clamping test
      declare
         Sat_Syn : aliased Synapse :=
           (Header => <>, Charge => 0, Threshold_Hi => 20, -- won't fire on 10
            Threshold_Lo => (Present => False), Reset_Mode_Field => To_Zero,
            Decay => (Present => False), Action => (Kind => Reject_If_Saturated_Action),
            Max_Charge_Cap => 10, Min_Charge_Cap => -10,
            Sdrp_Thread => <>, others => <>);
      begin
         St := Synapse_Apply_Delta (Sat_Syn, 15);
         Check ("synapse: charge is correctly saturated/clamped to Max_Charge_Cap",
                Sat_Syn.Charge = 10 and St = Ok);
      end;

      -- Tap-level Rate-Limiting test
      declare
         T_Syn : aliased Synapse :=
           (Header => <>, Charge => 0, Threshold_Hi => 10,
            Threshold_Lo => (Present => False), Reset_Mode_Field => To_Zero,
            Decay => (Present => False), Action => (Kind => Reject_If_Saturated_Action),
            Max_Charge_Cap => 100, Min_Charge_Cap => -100,
            Sdrp_Thread => <>, others => <>);

         Tap : aliased Synapse_Tap :=
           (Header => <>, Target => Downgrade (T_Syn'Unchecked_Access),
            Is_Positive => True, N => 1, Min_Interval_Ticks => 5, Last_Signal_Tick => 0);
      begin
         St := Synapse_Signal ((Object => Tap'Unchecked_Access, Rights => Aura.Rights.Write));
         Check ("synapse: tap-level rate limiting accepts first signal", St = Ok);

         St := Synapse_Signal ((Object => Tap'Unchecked_Access, Rights => Aura.Rights.Write));
         Check ("synapse: tap-level rate limiting rejects too frequent signal", St = Would_Block);
      end;

      -- Cascade Fault Diagnostics test
      declare
         Syn_B : aliased Synapse :=
           (Header => <>, Charge => 0, Threshold_Hi => 1,
            Threshold_Lo => (Present => False), Reset_Mode_Field => To_Zero,
            Decay => (Present => False),
            Action => (Kind => Feed_Synapse_Action,
                       Synapse_Target => (Target => null, Expected_Epoch => 0),
                       Feed_Kind => (Tag => Positive_Signal, Positive_N => 0)),
            Max_Charge_Cap => 100, Min_Charge_Cap => -100,
            Sdrp_Thread => <>, others => <>);

         Syn_A : aliased Synapse :=
           (Header => <>, Charge => 0, Threshold_Hi => 1,
            Threshold_Lo => (Present => False), Reset_Mode_Field => To_Zero,
            Decay => (Present => False),
            Action => (Kind => Feed_Synapse_Action,
                       Synapse_Target => Downgrade (Syn_B'Unchecked_Access),
                       Feed_Kind => (Tag => Positive_Signal, Positive_N => 0)),
            Max_Charge_Cap => 100, Min_Charge_Cap => -100,
            Sdrp_Thread => <>, others => <>);
      begin
         Syn_B.Action.Synapse_Target := Downgrade (Syn_A'Unchecked_Access);
         Last_Fired_Trace_Id := 0;
         St := Synapse_Apply_Delta (Syn_A, 1);
         Check ("synapse: cascade fault limits recursion and sets diagnostic tracepoint",
                St = Cascade_Too_Deep and Last_Fired_Trace_Id = 999999999);
      end;

      -- 10. Test Entropy budget feed and validation (Check_Valid)
      declare
         use Entropy_Test_Pkg;
         use type Interfaces.Unsigned_64;
         Dummy_Prm_Cap : aliased Integer := 123;
         Feed_St       : Kernel_Error;
         Init_Budget   : constant Interfaces.Unsigned_64 := Aura.Entropy.Entropy_Budget;
      begin
         -- Test with null capability (should fail with Bad_Cap)
         Dummy_Entropy_Feed (null, 100, Feed_St);
         Check ("entropy: feed with null cap fails with Bad_Cap", Feed_St = Bad_Cap);
         Check ("entropy: budget unchanged on failed feed", Aura.Entropy.Entropy_Budget = Init_Budget);

         -- Test with valid non-null capability
         Dummy_Entropy_Feed (Dummy_Prm_Cap'Unchecked_Access, 500, Feed_St);
         Check ("entropy: feed with valid cap succeeds", Feed_St = Ok);
         Check ("entropy: budget correctly updated on successful feed", Aura.Entropy.Entropy_Budget = Init_Budget + 500);
      end;
   end Test_New_Enhancements;

   procedure Test_Namespace_Operations is
      use Aura.Namespace;
      Root : aliased Namespace_Node;
      St   : Kernel_Error;

      Dummy_Cap_1 : aliased Integer := 111;

      Node_Dev    : Namespace_Node_Access;
      Node_Lookup : Namespace_Node_Access;
   begin
      -- Initialize root node
      Root.Name := Name_Strings.To_Bounded_String ("/");

      -- 1. Create a subdirectory node "dev" under root
      Namespace_Create_Node (Root'Unchecked_Access, "dev", null, Node_Dev, St);
      Check ("namespace: create component dev ok", St = Ok and Node_Dev /= null);

      -- 2. Create another subdirectory with the same name (should fail with Already_Exists)
      declare
         Fail_Node : Namespace_Node_Access;
      begin
         Namespace_Create_Node (Root'Unchecked_Access, "dev", null, Fail_Node, St);
         Check ("namespace: duplicate component dev fails", St = Already_Exists);
      end;

      -- 3. Mount dummy capability 1 onto "/dev/entropy"
      Namespace_Mount (Node_Dev, "entropy", Dummy_Cap_1'Unchecked_Access, St);
      Check ("namespace: mount entropy cap succeeds", St = Ok);

      -- 4. Lookup path "dev/entropy"
      Namespace_Lookup (Root'Unchecked_Access, "dev/entropy", Node_Lookup, St);
      Check ("namespace: lookup dev/entropy succeeds", St = Ok and Node_Lookup /= null);
      if Node_Lookup /= null then
         Check ("namespace: lookup resolved correct associated capability",
                Node_Lookup.Associated = Dummy_Cap_1'Unchecked_Access);
      end if;

      -- 5. Lookup path "/dev/entropy" with leading slash
      Namespace_Lookup (Root'Unchecked_Access, "/dev/entropy", Node_Lookup, St);
      Check ("namespace: lookup with leading slash succeeds", St = Ok and Node_Lookup /= null);

      -- 6. Lookup non-existent component (should fail with Not_Found)
      Namespace_Lookup (Root'Unchecked_Access, "dev/not_exists", Node_Lookup, St);
      Check ("namespace: lookup non-existent component fails", St = Not_Found);
   end Test_Namespace_Operations;

   procedure Test_Untyped_Allocation is
      use Aura.Untyped;
      use type Ada.Containers.Count_Type;
      Region : aliased Untyped_Region :=
        (Header => <>, Phys_Addr_Base => 16#1000_0000#, Size_Bits => 20, Is_Device => False, Allocated_Bitmap => <>);
      Cap    : constant Untyped_Manage_Ref := (Object => Region'Unchecked_Access);
      St     : Kernel_Error;
   begin
      -- 1. Successful reservation of 256 bytes at offset 1024 (4 granules of 64 bytes)
      Try_Reserve_Range (Region, 1024, 256, St);
      Check ("untyped: first reserve range succeeds", St = Ok);

      -- 2. Duplicate/overlapping reservation should fail with Already_Exists
      Try_Reserve_Range (Region, 1024, 128, St);
      Check ("untyped: overlapping reserve range fails with Already_Exists", St = Already_Exists);

      -- 3. Dynamic bitmap vector expansion (using offset 8192, granule 128 in word 3)
      Try_Reserve_Range (Region, 8192, 64, St);
      Check ("untyped: reserve at higher offset succeeds", St = Ok);
      declare
         Bitmap : constant Bitmap_Vectors.Vector := Region.Allocated_Bitmap;
      begin
         Check ("untyped: bitmap expanded to cover word 3", Bitmap_Vectors.Length (Bitmap) >= 3);
      end;

      -- 4. Retype with overflow check on multiplication
      Untyped_Retype (Cap, 0, Interfaces.Unsigned_64'Last, 10, St);
      Check ("untyped: retype with arithmetic overflow fails with Overflow", St = Overflow);

      -- 5. Retype exceeding region bounds (offset + size > 1 MB)
      Untyped_Retype (Cap, 524288, 1, 524289, St);
      Check ("untyped: retype exceeding region size fails with Overflow", St = Overflow);
   end Test_Untyped_Allocation;

   procedure Test_Channel is
      use Aura.Channel;
      Ch   : aliased Channel;
      Ep_A : aliased Channel_Endpoint := (Header => <>, Channel => Ch'Unchecked_Access, Side => Side_A);
      Ep_B : aliased Channel_Endpoint := (Header => <>, Channel => Ch'Unchecked_Access, Side => Side_B);

      Write_Cap_A : constant Channel_Endpoint_Write_Ref := (Object => Ep_A'Unchecked_Access, Rights => Aura.Rights.Write);
      Read_Cap_B  : constant Channel_Endpoint_Read_Ref := (Object => Ep_B'Unchecked_Access, Rights => Aura.Rights.Read);

      Msg : Channel_Message := (Data => (others => 0), Data_Len => 0, Cap => (Present => False), Cause => (Present => False));
      St  : Kernel_Error;
   begin
      -- Test Send successfully
      Channel_Send (Write_Cap_A, Msg, St);
      Check ("channel: send message succeeds", St = Ok);

      -- Fill the queue to test overflow capacity
      -- Depth is 64, we already sent 1 message, so send 63 more
      for I in 1 .. 63 loop
         Channel_Send (Write_Cap_A, Msg, St);
      end loop;

      -- Next send should fail with Capacity_Exceeded, and NOT deadlock or crash!
      Channel_Send (Write_Cap_A, Msg, St);
      Check ("channel: send overflow returns Capacity_Exceeded", St = Capacity_Exceeded);

      -- Receive a message to free a slot
      declare
         Recv_Msg : Channel_Message;
      begin
         Channel_Recv (Read_Cap_B, (Present => False), Recv_Msg, St);
         Check ("channel: receive message succeeds", St = Ok);
      end;

      -- Send should succeed again now that there is space
      Channel_Send (Write_Cap_A, Msg, St);
      Check ("channel: send succeeds after pop", St = Ok);
   end Test_Channel;

   procedure Test_Synapse is
      use Aura.Synapse;
      use type Interfaces.Integer_32;
      use Aura.Cap_Policy;

      Gated : aliased Policy :=
        (Effect => Allow, Valid_From => 0, Valid_Until => 0,
         Budget => (Unlimited => True), Active => False, Dead => False);

      --  Синапс-гейт: верхний порог активирует политику, нижний
      --  (-спайк) деактивирует.
      Gate_Syn : aliased Synapse :=
        (Header => <>, Charge => 0, Threshold_Hi => 3,
         Threshold_Lo => (Present => True, Value => -2),
         Reset_Mode_Field => To_Zero,
         Decay => (Present => False),
         Action =>
           (Kind          => Gate_Policy_Action,
            Policy_Target => Gated'Unchecked_Access,
            Gate_On_Hi    => Activate,
            Gate_On_Lo    => Deactivate),
         Max_Charge_Cap => <>, Min_Charge_Cap => <>,
         Sdrp_Thread => <>, others => <>);

      Notif : constant Aura.Notification.Notification_Ref :=
        new Aura.Notification.Notification_Object;

      --  «Резкий» сигнал: вырожденный синапс с порогом 1.
      Sharp : aliased Synapse :=
        (Header => <>, Charge => 0, Threshold_Hi => 1,
         Threshold_Lo => (Present => False),
         Reset_Mode_Field => To_Zero,
         Decay => (Present => False),
         Action =>
           (Kind         => Signal_Notification_Action,
            Notif_Target => (Target => Notif,
                             Expected_Epoch => Notif.Header.Epoch),
            Notif_Bit    => 2#1#),
         Max_Charge_Cap => <>, Min_Charge_Cap => <>,
         Sdrp_Thread => <>, others => <>);

      St : Kernel_Error;
   begin
      --  Накопление до верхнего порога активирует мандат.
      St := Synapse_Apply_Delta (Gate_Syn, 2);
      Check ("synapse: below threshold no fire",
             St = Ok and then not Applicable (Gated, 0));
      St := Synapse_Apply_Delta (Gate_Syn, 1);
      Check ("synapse: hi fire activates policy",
             St = Ok and then Applicable (Gated, 0));
      Check ("synapse: reset to zero after fire", Gate_Syn.Charge = 0);

      --  -спайк до нижнего порога деактивирует.
      St := Synapse_Apply_Delta (Gate_Syn, -2);
      Check ("synapse: lo fire deactivates policy",
             St = Ok and then not Applicable (Gated, 0));

      --  Резкий сигнал (порог 1) сразу будит notification.
      St := Synapse_Apply_Delta (Sharp, 1);
      Check ("synapse: sharp signal fires notification",
             St = Ok and then Notif.Pending = 1);
   end Test_Synapse;

   procedure Test_Real_Subsystems is
      use Aura.Instances;
      use Aura.Secure_Binding;
      use Aura.Vspace;
      use Aura.Fault;
      use type Interfaces.Unsigned_8;
      use type Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_64;
      use type Aura.Thread.Thread_Access;
      use type Aura.Thread.Thread_State;

      -- 1. Test Weak_Ref Epoch Checks
      T      : aliased Aura.Thread.Thread;
      T_Back : Aura.Thread.Thread_Access;
      Alive  : Boolean;
   begin
      T.Header.Epoch := 5;
      declare
         W_Ref  : constant Thread_Weak_Ref_Base.Instance := Thread_Weak_Ref_Base.Downgrade (T'Unchecked_Access);
      begin
         Thread_Weak_Ref_Base.Upgrade (W_Ref, T_Back, Alive);
         Check ("weak_ref: upgrade succeeds on matching epoch", Alive and T_Back = T'Unchecked_Access);

         -- Now change epoch to simulate object destruction/recreation
         T.Header.Epoch := 6;
         declare
            T_Back_Fail : Aura.Thread.Thread_Access;
            Alive_Fail  : Boolean;
         begin
            Thread_Weak_Ref_Base.Upgrade (W_Ref, T_Back_Fail, Alive_Fail);
            Check ("weak_ref: upgrade fails on epoch mismatch", not Alive_Fail and T_Back_Fail = null);
         end;
      end;

      -- 2. Test Secure_Binding with real Page_Table_Root
      declare
         Owner_Vspace : aliased V_Space;
         Owner_Proc   : aliased Aura.Vspace.Process_Context;
         Res          : Secure_Binding_Resource (Mmio_Region);
         S_Manage     : Secure_Binding_Manage_Ref;
         St           : Kernel_Error;
         Dummy_Prm    : aliased Integer := 42;
      begin
         Owner_Vspace.Page_Table_Root := 16#CAFE_BAB0#;
         Owner_Proc.Vspace := Owner_Vspace'Unchecked_Access;
         Res.Mmio_Phys_Base := 16#9000_0000#;
         Res.Mmio_Size      := 8192;

         -- Null capability is correctly rejected
         Secure_Binding_Create (null, Res, Aura.Vspace.Process_Context_Ref'(Owner_Proc'Unchecked_Access), 0, S_Manage, St);
         Check ("secure_binding: create with null cap fails", St = Bad_Cap);

         Secure_Binding_Create (Dummy_Prm'Unchecked_Access, Res, Aura.Vspace.Process_Context_Ref'(Owner_Proc'Unchecked_Access), 0, S_Manage, St);
         Check ("secure_binding: create succeeds and maps resource", St = Ok and S_Manage.Object /= null);

         if S_Manage.Object /= null then
            Check ("secure_binding: correct physical resource size/tlb cached", S_Manage.Object.Kernel_Tlb /= 0);
            Resolve_External_Effect (S_Manage.Object.all);
            Check ("secure_binding: resolve_external_effect unmaps and resets tlb", S_Manage.Object.Kernel_Tlb = 0);
         end if;
      end;

      -- 3. Test Fault_Resume and Sched_Resume
      declare
         Fault_Th : aliased Aura.Thread.Thread;
         Manage   : Thread_Manage_Ref;
         Phys     : Phys_Addr_Option := (Present => True, Value => 16#F000_0000#);
         St       : Kernel_Error;
      begin
         Fault_Th.State := Aura.Thread.Blocked;
         Manage.Object := Fault_Th'Unchecked_Access;
         Thread_Resume (Manage, Phys, 16#8000_0000#, St);
         Check ("fault: thread_resume maps segment and transitions thread to Ready", St = Ok and Fault_Th.State = Aura.Thread.Ready);
      end;

      -- 4. Test Double Cap_Revoke Guard
      declare
         use Aura.Cap_Node;
         Node : Cap_Node_Access;
         St   : Kernel_Error;
      begin
         Alloc (Obj_Epoch => 123, Result => Node, Status => St);
         Check ("cap_node: alloc for double-revoke test succeeds", St = Ok and Node /= null);
         if Node /= null then
            Cap_Revoke (Node, St);
            Check ("cap_node: first revoke succeeds", St = Ok);
            Check ("cap_node: revoke in progress is set", Node.Revoke_In_Progress);

            -- Call revoke again - should be guarded and return Ok safely without re-retiring
            Cap_Revoke (Node, St);
            Check ("cap_node: second revoke guarded and returns Ok", St = Ok);
         end if;
      end;

      -- 5. Test RCU Immediate Writer-Side Execution (Active_Readers = 0)
      declare
         use Aura.Rcu;
         use type System.Address;

         Allocated_Val : Layer_Access := new Integer'(99);
         Cb : Rcu_Callback := (Kind => Drop_Layer, Layer_Ref => Allocated_Val);
         St : Kernel_Error;
      begin
         -- No read lock is held, so Global_Domain.Readers_Count should be 0.
         Check ("rcu: readers count is 0", Global_Domain.Readers_Count = 0);

         Global_Domain.Call_Rcu (Cb, St);
         Check ("rcu: call_rcu with 0 readers executes immediately", St = Ok);
      end;

      -- 6. Test MAC Mandatory Label Setting and Strong Tranquility
      declare
         use Aura.Mac;
         use Aura.Namespace;

         Node  : aliased Namespace_Node;
         Lbl_1 : constant Mandatory_Label := (Level => 2, Categories => 2#110#);
         Lbl_2 : constant Mandatory_Label := (Level => 5, Categories => 2#001#);
         St    : Kernel_Error;
      begin
         Check ("mac: initially label is not set", not Node.Mac_Label_Set);

         -- First set should succeed
         Set_Mandatory_Label (Node, Lbl_1, St);
         Check ("mac: first label set succeeds", St = Ok and Node.Mac_Label_Set);
         Check ("mac: node level is correctly set", Node.Mac_Level = 2);
         Check ("mac: node categories are correctly set", Node.Mac_Categories = 2#110#);

         -- Second set should fail with Label_Immutable (Strong Tranquility)
         Set_Mandatory_Label (Node, Lbl_2, St);
         Check ("mac: second label set fails with Label_Immutable", St = Label_Immutable);
         Check ("mac: level remains unchanged", Node.Mac_Level = 2);
      end;

      -- 7. Test integration of previously orphan modules
      declare
         use Aura.Instances;

         -- Test Per_Cpu
         My_Cpu_Data : Cpu_Data.Instance := Cpu_Data.Create (0);
         Val : Integer;
      begin
         -- Retrieve from Per_Cpu (Cpu_Data)
         Val := Cpu_Data.Get (My_Cpu_Data, 0);
         Check ("per_cpu: Cpu_Data defaults to 0", Val = 0);
         Cpu_Data.Set (My_Cpu_Data, 0, 777);
         Check ("per_cpu: Cpu_Data retrieved successfully", Cpu_Data.Get (My_Cpu_Data, 0) = 777);

         -- Test Cap_Object_Ref_Pkg
         declare
            use Aura.Cap_Object_Ref_Pkg;
            use type System.Address;
            Dummy_Object : aliased Integer := 42;
            Dummy_Addr   : constant System.Address := Dummy_Object'Address;
            Ref1         : Instance;
         begin
            Register_Target (Dummy_Addr, 100);
            Check ("cap_object_ref: initial registered count is 1", Get_Ref_Count (Dummy_Addr) = 1);

            Ref1.Target := Dummy_Addr;
            Ref1.Epoch := 100;
            Adjust (Ref1);
            Check ("cap_object_ref: count after adjust is 2", Get_Ref_Count (Dummy_Addr) = 2);

            Finalize (Ref1);
            Check ("cap_object_ref: count after finalize is 1", Get_Ref_Count (Dummy_Addr) = 1);

            Finalize (Ref1);
            Check ("cap_object_ref: count after hitting zero is 0", Get_Ref_Count (Dummy_Addr) = 0);
         end;
      end;

      -- 8. Test Driver Reincarnation
      declare
         use Aura.Driver;
         use type Interfaces.Unsigned_32;
         use type Interfaces.Unsigned_64;

         Dummy_Proc : aliased Aura.Vspace.Process_Context;

         Dev  : aliased Device_Object :=
           (Header                => <>,
            Class                 => Platform_Other,
            State                 => 0,
            Platform_Id           => 1234,
            Parent                => (Present => False),
            Driver_Endpoint_Cap   => new Erased_Cap'(null),
            Iommu_Domain_Cap      => (Present => False),
            Prm_Resource_Set_Cap  => new Erased_Cap'(null),
            Supervision_Contract  => (Present => False));

         Contract : aliased Aura.Driver.Reincarnation_Contract :=
           (Supervised          => Aura.Vspace.Process_Context_Ref'(Dummy_Proc'Unchecked_Access),
            Respawn_Cap         => new Integer'(22),
            Restart_Count       => 0,
            Last_Heartbeat_Tick => 0);
      begin
         Check ("driver: initial state is Enumerated", Aura.Driver.State (Dev) = Enumerated);

         Aura.Driver.Respawn_Driver_Process (Dev, Contract, 100);

         Check ("driver: state after respawn is Bound", Aura.Driver.State (Dev) = Bound);
         Check ("driver: restart count incremented", Contract.Restart_Count = 1);
         Check ("driver: heartbeat updated", Contract.Last_Heartbeat_Tick = 100);
         Check ("driver: supervised process context is non-null", Contract.Supervised /= null);
         Check ("driver: driver endpoint is non-null", Dev.Driver_Endpoint_Cap.all /= null);
         Check ("driver: prm resource cap is non-null", Dev.Prm_Resource_Set_Cap.all /= null);
      end;

      -- 9. Test Synapse Rate-Limiting Cascaded Feed
      declare
         use Aura.Synapse;
         use type Interfaces.Integer_32;

         Target_Syn : aliased Synapse :=
           (Header => <>, Charge => 0, Threshold_Hi => 5,
            Threshold_Lo => (Present => False), Reset_Mode_Field => To_Zero,
            Decay => (Present => False), Action => (Kind => Reject_If_Saturated_Action),
            Max_Charge_Cap => 10, Min_Charge_Cap => -10,
            Sdrp_Thread => <>, Min_Interval_Ticks => 10, Last_Signal_Tick => 0);

         St : Kernel_Error;
      begin
         -- First signal at tick 100
         Aura.Timer.Global_Tick := 100;
         St := Synapse_Apply_Delta (Target_Syn, 1);
         Check ("synapse_rate_limit: first signal accepted", St = Ok);

         -- Second signal too fast at tick 102 (difference 2 < 10)
         Aura.Timer.Global_Tick := 102;
         St := Synapse_Apply_Delta (Target_Syn, 1);
         Check ("synapse_rate_limit: second too fast signal rejected", St = Would_Block);

         -- Third signal at tick 115 (difference 13 >= 10)
         Aura.Timer.Global_Tick := 115;
         St := Synapse_Apply_Delta (Target_Syn, 1);
         Check ("synapse_rate_limit: signal after interval accepted", St = Ok);
      end;

      -- 10. Test RCU XPC Error Reply Force
      declare
         use type Aura.Thread.Thread_State;
         use type Aura.Io_Ring.Thread_Access;

         Victim_Vspace : aliased Aura.Io_Ring.V_Space;
         T_Migrated : aliased Aura.Thread.Thread;
      begin
         T_Migrated.State := Aura.Thread.Blocked;
         T_Migrated.Migration_List_Next := null;

         -- Add to migrated list
         Victim_Vspace.Migrated_Threads := T_Migrated'Unchecked_Access;

         -- Destroy Vspace, which must resume the migrated thread
         Aura.Io_Ring.Object_Destroy_Vspace (Victim_Vspace);

         Check ("io_ring: destroyed vspace resumed migrated thread", T_Migrated.State = Aura.Thread.Ready);
         Check ("io_ring: migrated threads list cleared", Victim_Vspace.Migrated_Threads = null);
      end;
   end Test_Real_Subsystems;

begin
   Test_Rights;
   Test_Wait_Queue;
   Test_Notification;
   Test_Scheduler;
   Test_Attr_Watch;
   Test_Cap_Policy;
   Test_Namespace_Operations;
   Test_Untyped_Allocation;
   Test_Channel;
   Test_Synapse;
   Test_Sealed_Call;
   Test_Package_Fs;
   Test_Cap_Node_Alloc;
   Test_Iommu;
   Test_CDT_And_Slab;
   Test_Budget_Donation;
   Test_Deadline_Timers;
   Test_EDF_Scheduling;
   Test_CBS_Scheduling;
   Test_EBR_Reclamation;
   Test_Group_Reincarnation;
   Test_Io_Batch_And_Template;
   Test_Conceptual_Extensions;
   Test_RCU_Epoch;
   Test_Fault_Delegation;
   Test_NMI_Watchdog;
   Test_Interrupt_Threading;
   Test_New_Enhancements;
   Test_Real_Subsystems;

   if Failures = 0 then
      Put_Line ("aura selftest: OK");
   else
      Put_Line ("aura selftest:" & Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Aura_Selftest;
