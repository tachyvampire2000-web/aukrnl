--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива).

with Aura.Sched;
with Aura.Timer;

package body Aura.Watchdog is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Ada.Containers.Count_Type;
   use type Aura.Thread.Thread_Access;
   use type Aura.Notification.Notification_Ref;
   use type Aura.Reincarnation.Reincarnation_Contract_Access;

   function Saturating_Sub_U64
     (A, B : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is (if A >= B then A - B else 0);

   function Downgrade (Strong : Thread_Ref) return Thread_Weak_Ref is
     (Target         => Strong,
      Expected_Epoch => (if Strong /= null then Strong.Header.Epoch else 0));

   function Downgrade
     (Strong : Notification_Ref) return Notification_Weak_Ref
   is
     (Target         => Strong,
      Expected_Epoch => (if Strong /= null then Strong.Header.Epoch else 0));

   function Downgrade
     (Strong : Reincarnation_Contract_Ref) return Contract_Weak_Ref
   is
     (Target         => Strong,
      Expected_Epoch => (if Strong /= null then Strong.Header.Epoch else 0));

   procedure Upgrade
     (Self  : Thread_Weak_Ref;
      Value : out Thread_Ref;
      Alive : out Boolean)
   is
   begin
      if Self.Target /= null
        and then Self.Target.Header.Epoch = Self.Expected_Epoch
      then
         Value := Self.Target;
         Alive := True;
      else
         Value := null;
         Alive := False;
      end if;
   end Upgrade;

   procedure Upgrade
     (Self  : Notification_Weak_Ref;
      Value : out Notification_Ref;
      Alive : out Boolean)
   is
   begin
      if Self.Target /= null
        and then Self.Target.Header.Epoch = Self.Expected_Epoch
      then
         Value := Self.Target;
         Alive := True;
      else
         Value := null;
         Alive := False;
      end if;
   end Upgrade;

   procedure Upgrade
     (Self  : Contract_Weak_Ref;
      Value : out Reincarnation_Contract_Ref;
      Alive : out Boolean)
   is
   begin
      if Self.Target /= null
        and then Self.Target.Header.Epoch = Self.Expected_Epoch
      then
         Value := Self.Target;
         Alive := True;
      else
         Value := null;
         Alive := False;
      end if;
   end Upgrade;

   function Check_Valid (Cap : Thread_Read_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   function Check_Valid (Cap : Notification_Write_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   function Check_Valid (Cap : Contract_Read_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   function Check_Valid (Cap : Watchdog_Manage_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   procedure Construct_Watchdog
     (Watched    : Thread_Weak_Ref;
      Period     : Interfaces.Unsigned_32;
      Notify_Ref : Notification_Weak_Ref;
      Policy     : Watchdog_Policy;
      Contract   : Contract_Weak_Ref;
      Result     : out Watchdog_Ref)
   is
   begin
      Result := new Watchdog'
        (Header     => <>,
         Watched    => Watched,
         Period     => Period,
         Notify_Ref => Notify_Ref,
         Policy     => Policy,
         Contract   => Contract);
   end Construct_Watchdog;

   procedure Cap_Mint_Root
     (Wd : Watchdog_Ref; Result : out Watchdog_Manage_Ref)
   is
   begin
      Result := (Object => Wd);
   end Cap_Mint_Root;

   procedure Remove_By_Address
     (Reg : in out Watchdog_Vectors.Vector; Wd : Watchdog_Ref)
   is
      use type Watchdog_Vectors.Extended_Index;
      I : Positive := 1;
   begin
      while I <= Natural (Watchdog_Vectors.Length (Reg)) loop
         if Watchdog_Vectors.Element (Reg, I) = Wd then
            Watchdog_Vectors.Delete (Reg, I);
         else
            I := I + 1;
         end if;
      end loop;
   end Remove_By_Address;

   procedure Heartbeat_Touch is
   begin
      Aura.Sched.Current_Thread.Last_Syscall_Tick :=
        Aura.Timer.Current_Tick;  --  Release-запись через Volatile-поле
   end Heartbeat_Touch;

   procedure Watchdog_Create
     (Watched  : Thread_Read_Ref;
      Notify_C : Notification_Write_Ref;
      Period   : Interfaces.Unsigned_32;
      Policy   : Watchdog_Policy;
      Contract : Reincarnation_Contract_Read_Ref_Option;
      Result   : out Watchdog_Manage_Ref;
      Status   : out Kernel_Error)
   is
      Wd  : Watchdog_Ref;
      Reg : Watchdog_Vectors.Vector (Watchdog_Max);
   begin
      Result := (Object => null);
      Status := Check_Valid (Watched);
      if Status /= Ok then
         return;
      end if;
      Status := Check_Valid (Notify_C);
      if Status /= Ok then
         return;
      end if;
      if Contract.Present then
         Status := Check_Valid (Contract.Value);
         if Status /= Ok then
            return;
         end if;
      end if;

      Construct_Watchdog
        (Watched => Downgrade (Watched.Object),
         Period => Period, Notify_Ref => Downgrade (Notify_C.Object),
         Policy => Policy,
         Contract => (if Contract.Present
                      then Downgrade (Contract.Value.Object)
                      else Empty_Weak_Ref),
         Result => Wd);

      Watchdogs.Lock (Reg);
      if Watchdog_Vectors.Length (Reg) >= Watchdog_Max then
         Watchdogs.Unlock (Reg);
         Status := Capacity_Exceeded;
         return;
      end if;
      Watchdog_Vectors.Append (Reg, Wd);
      Watchdogs.Unlock (Reg);

      Cap_Mint_Root (Wd, Result);
      Status := Ok;
   end Watchdog_Create;

   procedure Watchdog_Destroy
     (Wd : Watchdog_Manage_Ref; Status : out Kernel_Error)
   is
      Reg : Watchdog_Vectors.Vector (Watchdog_Max);
   begin
      Status := Check_Valid (Wd);
      if Status /= Ok then
         return;
      end if;
      Watchdogs.Lock (Reg);
      Remove_By_Address (Reg, Wd.Object);
      Watchdogs.Unlock (Reg);
      Status := Ok;
   end Watchdog_Destroy;

   procedure Apply_Watchdog_Policy
     (Wd : Watchdog; Watched : in out Aura.Thread.Thread)
   is
      Contract_Alive : Boolean;
      Contract_Ref   : Reincarnation_Contract_Ref;
   begin
      case Wd.Policy is
         when Notify =>
            null;  --  Поведение T64 0.3.7: уведомление — единственное
                    --  действие.
         when Kill_And_Respawn =>
            --  Переиспользует уже существующий Supervisor_Tick (§16.2
            --  порта) — не дублирует Kill_Process/Respawn_From_Template
            --  здесь. Без Contract — деградация до Notify: лучше
            --  уведомление без перезапуска, чем попытка перезапустить
            --  процесс, для которого у Watchdog нет
            --  Reincarnation_Contract.
            --
            --  OPEN (перенесено дословно из Rust-версии, todo!() в
            --  apply_watchdog_policy, §15): Supervisor_Tick принимает
            --  "in out" Reincarnation_Contract, и нигде в §16 порта не
            --  специфицирован способ синхронизации доступа — обычный
            --  supervisor явно владеет эксклюзивным доступом, а здесь
            --  Watchdog_Tick (другой, асинхронный по отношению к
            --  supervisor вызыватель) тоже хочет вызвать ту же функцию.
            --  Это настоящая гонка данных, если оба пути сработают на
            --  одном контракте одновременно, и спецификация
            --  синхронизации Reincarnation_Contract — отдельный
            --  нерешённый вопрос, выходящий за рамки T82 (см. дорожную
            --  карту: следует завести отдельный тикет на per-contract
            --  lock, а не решать его здесь неявно). Порт НЕ придумывает
            --  решение этой гонки от себя — она перенесена как открытая,
            --  ровно как в Rust-версии.
            Upgrade (Wd.Contract, Contract_Ref, Contract_Alive);
            if Contract_Alive then
               raise Program_Error with
                 "OPEN: требует решения по синхронизации " &
                 "Reincarnation_Contract — см. комментарий выше " &
                 "(перенесено из todo!() Rust-версии, не разрешено " &
                 "и здесь)";
            end if;
         when Freeze =>
            --  Переиспользует уже существующее состояние Suspended (T57,
            --  §5.7.1 порта) — не вводит новый вариант Thread_State ради
            --  одной policy-ветки.
            Watched.State := Aura.Thread.Suspended;
      end case;
   end Apply_Watchdog_Policy;

   procedure Watchdog_Tick (Now : Interfaces.Unsigned_64) is
      Reg           : Watchdog_Vectors.Vector (Watchdog_Max);
      Watched_Alive : Boolean;
      Watched       : Thread_Ref;
      Notif_Alive   : Boolean;
      Notif         : Notification_Ref;
      Last          : Interfaces.Unsigned_64;
   begin
      Watchdogs.Lock (Reg);
      for I in 1 .. Natural (Watchdog_Vectors.Length (Reg)) loop
         declare
            Wd : constant Watchdog_Ref := Watchdog_Vectors.Element (Reg, I);
         begin
            Upgrade (Wd.Watched, Watched, Watched_Alive);
            if Watched_Alive then
               Last := Watched.Last_Syscall_Tick;
               if Saturating_Sub_U64 (Now, Last)
                    > Interfaces.Unsigned_64 (Wd.Period)
               then
                  Upgrade (Wd.Notify_Ref, Notif, Notif_Alive);
                  if Notif_Alive then
                     Aura.Notification.Notification_Signal (Notif);
                  end if;
                  Apply_Watchdog_Policy (Wd.all, Watched.all);
               end if;
            end if;
         end;
      end loop;
      Watchdogs.Unlock (Reg);
   end Watchdog_Tick;

end Aura.Watchdog;
