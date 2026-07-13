--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Object; use Aura.Object;
with Interfaces;

package Aura.Reincarnation is

   pragma SPARK_Mode (On);

   type Process_Context_Ref is access all Integer; -- Placeholder
   type Cap_Any_Ref is access all Integer; -- Placeholder
   type Cap_Snapshot is access all Integer; -- Placeholder

   type Reincarnation_Contract;
   type Reincarnation_Contract_Access is access all Reincarnation_Contract;
   type Reincarnation_Contract_Ref_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Reincarnation_Contract_Access;
         when False => null;
      end case;
   end record;


   type Restart_Strategy is (One_For_One, One_For_All, Rest_For_One);

   type Escalation_Policy is
     (Notify_Supervisor, Terminate_Container, Kernel_Panic);

   type Reincarnation_Contract is limited record
      Header                : Object_Header;
      Supervised             : Process_Context_Ref;
      Supervisor             : Process_Context_Ref;
      Heartbeat_Timeout_Ms    : Interfaces.Unsigned_32;
      Last_Heartbeat_Tick     : aliased Interfaces.Unsigned_64;
      Respawn_Cap             : Cap_Any_Ref;
      Restart_Count           : Interfaces.Unsigned_32;
      Max_Restarts            : Interfaces.Unsigned_32;
      Escalation_Policy_Field : Escalation_Policy;
      Mount_Log_Write_Cap     : Cap_Any_Ref;
      Mount_Log_Phys_Base     : Interfaces.Unsigned_64;
      Mount_Log_Capacity      : Interfaces.Unsigned_32;
      Free_Slot_Bitmap        : Interfaces.Unsigned_64;
      Max_Mounts              : Interfaces.Unsigned_32;
      Mounts_Since_Prune       : aliased Interfaces.Unsigned_32;
      Restart_Strategy_Field   : Restart_Strategy;
      Group_Head               : Reincarnation_Contract_Ref_Option;
      Next_In_Group             : Reincarnation_Contract_Access;
      Sibling_Order             : Interfaces.Unsigned_32;
   end record
     with Volatile;


   --  (продолжение из источника, doc-lines 5452-5463, после
   --  первоначального закрытия Aura.Reincarnation — см. MANIFEST §Находки)
   type Mount_Log_Name is array (0 .. 127) of Interfaces.Unsigned_8;

   type Mount_Log_Entry is record
      Source_Cap : Cap_Snapshot;
      Priority   : Interfaces.Unsigned_32;
      As_Union   : Boolean;
      Lease_Ms   : Interfaces.Unsigned_32;
      Name       : Mount_Log_Name;
   end record
     with Convention => C;

end Aura.Reincarnation;
