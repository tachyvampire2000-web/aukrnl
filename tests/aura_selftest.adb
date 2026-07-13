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

   if Failures = 0 then
      Put_Line ("aura selftest: OK");
   else
      Put_Line ("aura selftest:" & Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Aura_Selftest;
