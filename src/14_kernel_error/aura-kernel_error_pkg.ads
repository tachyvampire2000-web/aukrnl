--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

package Aura.Kernel_Error_Pkg is

   pragma Pure;

   --  Порядок объявления — строго по возрастанию числового кода (Ada RM
   --  13.4 требует этого для representation clause ниже). Не совпадает
   --  с порядком по смысловым категориям Rust-документа — см. пояснение
   --  выше.
   type Kernel_Error is
     (Driver_Restarting,     --  запрос к устройству в окне перезапуска
                              --  драйвера
      Hardware_Fault,
      User_Fault,             --  Fault-адрес передаётся отдельно
                               --  (например, в регистре или через
                               --  Fault_Message), т.к. представление
                               --  enum несовместимо с кортежными
                               --  вариантами — идентично обоснованию
                               --  Rust-версии
      Host_Vspace_Destroyed,  --  аварийный XpcReply при Object_Destroy
                               --  VSpace
      Max_Waiters,             --  Wait_Queue_Max_Waiters превышен
      Invalid_Device_State, Access_Violation, Not_Supported,
      Already_Exists, Invalid_Argument,
      Perm_Denied,            --  используется в Check_Right;
                               --  Permission_Denied убран как дубль
      Not_Found,
      Expired,                --  T27: временный мандат истёк
                               --  (Valid_Until прошёл)
      Not_Yet_Valid,          --  T27: мандат ещё не вступил в силу
                               --  (Valid_From в будущем)
      Read_Down_Violation,    --  T59: Biba — чтение объекта с более
                               --  низкой целостностью
      Write_Up_Violation,     --  T59: Biba — запись в объект с более
                               --  высокой целостностью
      Label_Immutable, Category_Mismatch, Write_Down_Violation,
      Read_Up_Violation,
      Cascade_Too_Deep,       --  Synapse_Fire: глубина каскада >
                               --  Synapse_Max_Fire_Depth (T108/T94/T95,
                               --  §16a порта)
      Entropy_Exhausted,      --  T43
      Interrupted, Timeout, Would_Block,
      Object_Destroyed, Timed_Out, Unknown_Op,
      Illegal_Instruction, Fault_In_Thread,
      Elf_Load_Error, Invalid_Elf_Format,
      Irq_Table_Full, Not_Granted, No_Device_Attached, Iommu_Table_Full,
      Origin_Revoked, Path_Conflict, Mount_Conflict, Would_Create_Cycle,
      Mount_Quota_Exceeded, Invalid_Name, Name_Too_Long,
      Overflow, Mapping_Conflict, Invalid_Address, Out_Of_Memory,
      Range_Occupied, Bad_Cap, Reply_Consumed, Revoked_During_Mint,
      Parent_Revoking, Cdt_Too_Deep, Bad_Rights, Revoked, Ring_Demotion,
      Ring_Violation, Syscall_Not_Permitted, Invalid_Temporal_Range,
      Capability_Expired, Capacity_Exceeded, Invalid_Cap,
      Ok);  --  добавлено для Ada-идиомы "Status : out Kernel_Error;
             --  Status = Ok" — в Rust-версии успех кодируется отдельно
             --  через Result<T, KernelError>, здесь — явное значение Ok
             --  с кодом 0, не пересекающееся ни с одним отрицательным
             --  кодом ошибки Rust-версии. Стоит последним в списке
             --  (не первым) — см. пояснение о монотонности выше.

   for Kernel_Error use
     (Driver_Restarting => -122, Hardware_Fault => -121,
      User_Fault => -120, Host_Vspace_Destroyed => -119,
      Max_Waiters => -118, Invalid_Device_State => -117,
      Access_Violation => -116, Not_Supported => -115,
      Already_Exists => -114, Invalid_Argument => -113,
      Perm_Denied => -111, Not_Found => -110, Expired => -107,
      Not_Yet_Valid => -106, Read_Down_Violation => -105,
      Write_Up_Violation => -104, Label_Immutable => -103,
      Category_Mismatch => -102, Write_Down_Violation => -101,
      Read_Up_Violation => -100, Cascade_Too_Deep => -95,
      Entropy_Exhausted => -90, Interrupted => -82, Timeout => -81,
      Would_Block => -80, Object_Destroyed => -72, Timed_Out => -71,
      Unknown_Op => -70, Illegal_Instruction => -61,
      Fault_In_Thread => -60, Elf_Load_Error => -51,
      Invalid_Elf_Format => -50, Irq_Table_Full => -44,
      Not_Granted => -43, No_Device_Attached => -41,
      Iommu_Table_Full => -40, Origin_Revoked => -36,
      Path_Conflict => -35, Mount_Conflict => -34,
      Would_Create_Cycle => -33, Mount_Quota_Exceeded => -32,
      Invalid_Name => -31, Name_Too_Long => -30, Overflow => -23,
      Mapping_Conflict => -22, Invalid_Address => -21,
      Out_Of_Memory => -20, Range_Occupied => -15, Bad_Cap => -14,
      Reply_Consumed => -13, Revoked_During_Mint => -12,
      Parent_Revoking => -11, Cdt_Too_Deep => -10, Bad_Rights => -9,
      Revoked => -8, Ring_Demotion => -7, Ring_Violation => -6,
      Syscall_Not_Permitted => -5, Invalid_Temporal_Range => -4,
      Capability_Expired => -3, Capacity_Exceeded => -2,
      Invalid_Cap => -1, Ok => 0);

   for Kernel_Error'Size use 32;

end Aura.Kernel_Error_Pkg;
