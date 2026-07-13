--  AURA — Watchdog (T64/T82): наблюдение за heartbeat потоков.
--  Каждый Watchdog хранит слабую ссылку на наблюдаемый поток и
--  Notification для сигнализации; Watchdog_Tick вызывается из
--  таймерного прерывания и проверяет просрочку heartbeat.

with Aura.Object;           use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Ticket_Lock;
with Aura.Thread;
with Aura.Notification;
with Aura.Reincarnation;
with Ada.Containers.Bounded_Vectors;
with Interfaces;

package Aura.Watchdog is

   pragma SPARK_Mode (Off);

   subtype Thread_Ref is Aura.Thread.Thread_Access;
   subtype Notification_Ref is Aura.Notification.Notification_Ref;
   subtype Reincarnation_Contract_Ref is
     Aura.Reincarnation.Reincarnation_Contract_Access;

   --  Слабые ссылки: адрес + ожидаемая эпоха (см. Aura.Weak_Ref;
   --  Volatile-объекты требуют собственных мономорфных типов вместо
   --  generic-инстанциации — см. RM C.6 о согласовании Volatile
   --  formal/actual).
   type Thread_Weak_Ref is record
      Target         : Thread_Ref;
      Expected_Epoch : Interfaces.Unsigned_32 := 0;
   end record;

   type Notification_Weak_Ref is record
      Target         : Notification_Ref;
      Expected_Epoch : Interfaces.Unsigned_32 := 0;
   end record;

   type Contract_Weak_Ref is record
      Target         : Reincarnation_Contract_Ref;
      Expected_Epoch : Interfaces.Unsigned_32 := 0;
   end record;

   Empty_Weak_Ref : constant Contract_Weak_Ref :=
     (Target => null, Expected_Epoch => 0);

   function Downgrade (Strong : Thread_Ref) return Thread_Weak_Ref;
   function Downgrade
     (Strong : Notification_Ref) return Notification_Weak_Ref;
   function Downgrade
     (Strong : Reincarnation_Contract_Ref) return Contract_Weak_Ref;

   procedure Upgrade
     (Self  : Thread_Weak_Ref;
      Value : out Thread_Ref;
      Alive : out Boolean);
   procedure Upgrade
     (Self  : Notification_Weak_Ref;
      Value : out Notification_Ref;
      Alive : out Boolean);
   procedure Upgrade
     (Self  : Contract_Weak_Ref;
      Value : out Reincarnation_Contract_Ref;
      Alive : out Boolean);

   --  Мандаты (рантайм-представление прав — см. §1 порта).
   type Thread_Read_Ref is record
      Object : Thread_Ref;
   end record;

   type Notification_Write_Ref is record
      Object : Notification_Ref;
   end record;

   type Contract_Read_Ref is record
      Object : Reincarnation_Contract_Ref;
   end record;

   type Reincarnation_Contract_Read_Ref_Option
     (Present : Boolean := False)
   is record
      case Present is
         when True  => Value : Contract_Read_Ref;
         when False => null;
      end case;
   end record;

   --  T82: реакция на просрочку heartbeat. Расширяет T64 — раньше
   --  единственным действием был Notification_Signal без различения
   --  серьёзности.
   type Watchdog_Policy is
     (Notify,          --  Только уведомить через Notification — решение
                        --  принимает наблюдатель.
      Kill_And_Respawn, --  Убить поток и немедленно перезапустить из
                         --  шаблона (делегирует в тот же путь, что и
                         --  Reincarnation_Contract, §16.2 порта).
      Freeze);          --  Заморозить поток (не убивать, не
                         --  возобновлять) — для отладки зависших
                         --  состояний без потери контекста на момент
                         --  таймаута.
   for Watchdog_Policy use (Notify => 0, Kill_And_Respawn => 1, Freeze => 2);
   for Watchdog_Policy'Size use 8;

   type Watchdog is limited record
      Header    : Object_Header;
      Watched   : Thread_Weak_Ref;
      Period    : Interfaces.Unsigned_32;
      Notify_Ref : Notification_Weak_Ref;
      --  T82: что делать при просрочке, помимо Notification_Signal.
      Policy    : Watchdog_Policy;
      --  Нужен только для Kill_And_Respawn — реальный перезапуск
      --  делегирует в уже существующий Supervisor_Tick (§16.2 порта),
      --  а не дублируется здесь. Если Policy = Kill_And_Respawn, а
      --  Contract отсутствует — деградация до Notify (см.
      --  Apply_Watchdog_Policy) вместо паники: лучше уведомление без
      --  перезапуска, чем undefined behaviour.
      Contract  : Contract_Weak_Ref;
   end record;

   type Watchdog_Ref is access all Watchdog;

   type Watchdog_Manage_Ref is record
      Object : Watchdog_Ref;
   end record;

   function Check_Valid (Cap : Thread_Read_Ref) return Kernel_Error;
   function Check_Valid (Cap : Notification_Write_Ref) return Kernel_Error;
   function Check_Valid (Cap : Contract_Read_Ref) return Kernel_Error;
   function Check_Valid (Cap : Watchdog_Manage_Ref) return Kernel_Error;

   Watchdog_Max : constant := 256;

   --  T64: глобальный реестр живых Watchdog. Тот же паттерн, что
   --  Iommu_Mapping в §17 порта (Ticket_Lock (Bounded_Vector)) — не
   --  Slot_Map, потому что здесь нужна итерация по всем живым записям на
   --  каждом тике (Watchdog_Tick ниже), а Slot_Map (§A.4 порта) итерации
   --  не предоставляет и жёстко завязан на Cdt_Capacity.
   package Watchdog_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Watchdog_Ref);
   subtype Watchdog_Vector is Watchdog_Vectors.Vector (Watchdog_Max);
   package Watchdog_Locks is new Aura.Ticket_Lock
     (Watchdog_Vector);

   Watchdogs : Watchdog_Locks.Instance;

   --  T64: отметка heartbeat текущего потока (вызывается на каждом
   --  syscall-входе).
   procedure Heartbeat_Touch;

   --  T64: создать Watchdog поверх живого потока. Notification должен
   --  быть создан заранее вызывающим — Watchdog только сигналит, не
   --  владеет жизнью. Contract обязателен только для Kill_And_Respawn
   --  (см. деградацию в Apply_Watchdog_Policy, если всё же не передан).
   procedure Watchdog_Create
     (Watched  : Thread_Read_Ref;             --  требует Read
      Notify_C : Notification_Write_Ref;       --  требует Write
      Period   : Interfaces.Unsigned_32;
      Policy   : Watchdog_Policy;
      Contract : Reincarnation_Contract_Read_Ref_Option;  --  требует
                                                             --  Read, если
                                                             --  присутствует
      Result   : out Watchdog_Manage_Ref;
      Status   : out Kernel_Error);

   --  T64: снять наблюдение. Запись удаляется из Watchdogs немедленно —
   --  дальнейшие тики Watchdog_Tick этот Watchdog не видят. Идентичность
   --  сравнивается по адресу объекта, так как Bounded_Vector (в отличие
   --  от Slot_Map) не даёт стабильный индекс с поколением — это не нужно
   --  здесь: Watchdog не переживает Cap_Revoke и не переиспользуется,
   --  только удаляется.
   procedure Watchdog_Destroy
     (Wd : Watchdog_Manage_Ref; Status : out Kernel_Error);

   --  T82: применить policy сверх Notification_Signal при просрочке.
   procedure Apply_Watchdog_Policy
     (Wd : Watchdog; Watched : in out Aura.Thread.Thread);

   Nmi_Watchdog_Alarm_Triggered : aliased Boolean := False;

   --  T64: проверка всех живых Watchdog на просрочку heartbeat —
   --  вызывается из таймерного прерывания (§8 порта).
   procedure Watchdog_Tick (Now : Interfaces.Unsigned_64);

   function Saturating_Sub_U64
     (A, B : Interfaces.Unsigned_64) return Interfaces.Unsigned_64;

end Aura.Watchdog;
