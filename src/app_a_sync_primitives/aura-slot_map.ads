--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Interfaces;

generic
   type Element_Type is private;
   Capacity : Positive := 65536;  --  CDT_CAPACITY из Rust-версии
package Aura.Slot_Map is

   pragma SPARK_Mode (On);

   --  Идентификатор слота: индекс + поколение, как SlotId(u64) в Rust,
   --  но выражен как отдельные поля вместо battенных 32+32 бит —
   --  Ada-запись с двумя полями не требует ручного сдвига/маскирования,
   --  которое Rust-версия делала через (idx << 32) | gen.
   type Slot_Id is record
      Idx : Natural range 0 .. Capacity - 1;
      Gen : Interfaces.Unsigned_32;
   end record;

   Free_Sentinel : constant := Natural'Last;  --  эквивалент SLOT_FREE_SENTINEL

   type Instance is limited private;

   function Create return Instance;

   --  Эквивалент insert(). Возвращает Success = False при переполнении
   --  (Rust: Err(KernelError::CapacityExceeded)) — вызывающий код
   --  преобразует это в KernelError на уровне API (§1.2), Slot_Map сам
   --  не знает про KernelError, чтобы оставаться независимым generic-модулем.
   procedure Insert
     (Self    : in out Instance;
      Val     : Element_Type;
      Id      : out Slot_Id;
      Success : out Boolean);

   --  Эквивалент remove(). Found = False если Id устарел (поколение не
   --  совпадает) или слот уже пуст — как и в Rust, это не ошибка вызывающего,
   --  а нормальный случай "мандат уже отозван".
   procedure Remove
     (Self  : in out Instance;
      Id    : Slot_Id;
      Val   : out Element_Type;
      Found : out Boolean);

   function Get (Self : Instance; Id : Slot_Id) return Element_Type
     with Pre => Contains (Self, Id);

   function Contains (Self : Instance; Id : Slot_Id) return Boolean;

private

   type Slot_Record is record
      Gen       : Interfaces.Unsigned_32 := 0;  -- чётное = свободен (как в Rust)
      Next_Free : Natural := Natural'Last;
      Occupied  : Boolean := False;
      Data      : Element_Type;
   end record;

   type Slot_Array is array (0 .. Capacity - 1) of Slot_Record;

   type Instance is limited record
      Slots     : Slot_Array;
      Free_Head : Natural := 0;      --  индекс первого свободного, Natural'Last = None
      Has_Free  : Boolean := True;
      Count     : Natural := 0;
   end record;

end Aura.Slot_Map;
