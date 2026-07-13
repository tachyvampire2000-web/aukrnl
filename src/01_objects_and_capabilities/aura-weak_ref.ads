--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Interfaces;

generic
   type Element_Type (<>) is limited private with Volatile;
   type Element_Access is access all Element_Type;
package Aura.Weak_Ref is

   pragma SPARK_Mode (On);

   --  В отличие от Cap_Object_Ref (контролируемая СИЛЬНАЯ ссылка, §1.1
   --  порта), Weak_Ref НЕ продлевает время жизни объекта и не мешает его
   --  уничтожению. Вместо счётчика владения хранит адрес и ожидаемую
   --  эпоху объекта на момент создания слабой ссылки — Upgrade сверяет
   --  текущую эпоху объекта (если он ещё физически существует по этому
   --  адресу) с сохранённой при Downgrade, тем же способом, каким
   --  Check_Valid (§1.5 порта) сверяет эпохи мандата.
   type Instance is limited record
      Target         : Element_Access;
      Expected_Epoch : Interfaces.Unsigned_32;
   end record;

   --  Пустая слабая ссылка (эквивалент отсутствия Weak — например,
   --  начальное состояние Watchdog.Contract до присвоения).
   Empty : constant Instance := (Target => null, Expected_Epoch => 0);

   function Downgrade (Strong : Element_Access) return Instance
     with Global => null;

   --  Value = null и Alive = False, если объект уже уничтожен (эпоха не
   --  совпадает) либо Self был пустой слабой ссылкой изначально.
   procedure Upgrade
     (Self  : Instance;
      Value : out Element_Access;
      Alive : out Boolean)
     with Global => null;

end Aura.Weak_Ref;
