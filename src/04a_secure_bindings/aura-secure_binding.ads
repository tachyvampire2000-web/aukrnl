--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Object; use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights; use Aura.Rights;
with Interfaces;

package Aura.Secure_Binding is

   pragma SPARK_Mode (On);

   use type Interfaces.Unsigned_64;

   type Iommu_Domain_Ref is access all Integer; -- Placeholder
   type Process_Context_Weak_Ref is access all Integer; -- Placeholder
   type Prm_Resource_Set_Cap is access all Integer; -- Placeholder
   type Process_Context_Ref is access all Integer; -- Placeholder
   type Secure_Binding_Manage_Ref is access all Integer; -- Placeholder

   type Resource_Kind is (Mmio_Region, Dma_Buffer, Port_Io);

   type Secure_Binding_Resource (Kind : Resource_Kind := Mmio_Region) is record
      case Kind is
         when Mmio_Region =>
            Mmio_Phys_Base : Interfaces.Unsigned_64;
            Mmio_Size      : Interfaces.Unsigned_64;
         when Dma_Buffer =>
            Dma_Phys_Base   : Interfaces.Unsigned_64;
            Dma_Size        : Interfaces.Unsigned_64;
            Iommu_Domain    : Iommu_Domain_Ref;
         when Port_Io =>
            Base_Port : Interfaces.Unsigned_16;
            Count     : Interfaces.Unsigned_16;
      end case;
   end record;

   type Secure_Binding is limited record
      Header      : Object_Header;
      Resource    : Secure_Binding_Resource;
      Owner       : Process_Context_Weak_Ref;
      --  TLB-запись ядра для этой привязки (PA → VA в адресном пространстве
      --  owner). При revoke — запись немедленно аннулируется через
      --  Vspace_Unmap. Volatile-поле для атомарного доступа, эквивалент
      --  AtomicU64.
      Kernel_Tlb  : aliased Interfaces.Unsigned_64;
   end record
     with Volatile;

   --  При revoke Secure_Binding — немедленно убрать маппинг из VSpace
   --  процесса. Процесс теряет доступ к ресурсу до возврата из revoke.
   --  Реализует Has_External_Effect (§1.7.0 порта).
   procedure Resolve_External_Effect (Self : in out Secure_Binding)
     with Post => Self.Kernel_Tlb = 0;


   --  Создать защищённую привязку ресурса к процессу.
   --  Требует мандат с Bind_Prm (только PRM-процесс может создавать
   --  привязки).
   procedure Secure_Binding_Create
     (Prm_Cap  : Prm_Resource_Set_Cap;   --  требует Bind_Prm
      Resource : Secure_Binding_Resource;
      Owner    : Process_Context_Ref;
      Va_Hint  : Interfaces.Unsigned_64;  --  0 = ядро выбирает
      Result   : out Secure_Binding_Manage_Ref;
      Status   : out Kernel_Error);


end Aura.Secure_Binding;
