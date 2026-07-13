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

begin
   Test_Rights;
   Test_Wait_Queue;
   Test_Notification;
   Test_Scheduler;
   Test_Attr_Watch;

   if Failures = 0 then
      Put_Line ("aura selftest: OK");
   else
      Put_Line ("aura selftest:" & Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Aura_Selftest;
