--  Host/reference self-test для ядра AURA: проверяет базовые
--  инварианты (rights, wait queue, notification, scheduler, attr
--  watchers) на reference-бэкенде HAL. Завершает процесс кодом 0
--  только если все проверки прошли.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;
with Interfaces;

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
with Aura.Timer;

procedure Aura_Selftest is

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
            Sealed => Call'Unchecked_Access));
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
            Gate_On_Lo    => Deactivate));

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
            Notif_Bit    => 2#1#));

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

begin
   Test_Rights;
   Test_Wait_Queue;
   Test_Notification;
   Test_Scheduler;
   Test_Attr_Watch;
   Test_Cap_Policy;
   Test_Synapse;
   Test_Sealed_Call;
   Test_Package_Fs;
   Test_Cap_Node_Alloc;
   Test_Iommu;
   Test_CDT_And_Slab;
   Test_Budget_Donation;
   Test_Deadline_Timers;

   if Failures = 0 then
      Put_Line ("aura selftest: OK");
   else
      Put_Line ("aura selftest:" & Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Aura_Selftest;
