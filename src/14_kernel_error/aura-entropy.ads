--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Object; use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights; use Aura.Rights;
with Interfaces;

package Aura.Entropy is

   pragma SPARK_Mode (On);

   use type Interfaces.Unsigned_64;

   type Object_Bind_Prm_Ref is access all Integer; -- Placeholder

   --  Глобальный бюджет энтропии в байтах. Инициализируется при старте
   --  через аппаратный RNG (HAL.Rdrand).
   Entropy_Budget : aliased Interfaces.Unsigned_64 := 0;

   --  Максимальный бюджет: 1 МБ. Ограничивает накопление неиспользованной
   --  энтропии.
   Entropy_Budget_Max : constant := 2 ** 20;

   --  Запросить Bytes байт энтропии. Атомарно уменьшает бюджет; возвращает
   --  Entropy_Exhausted если бюджет исчерпан.

   --  Пополнить бюджет (вызывается из Entropy_Feed syscall или
   --  аппаратного IRQ). Насыщающее сложение — не выходит за
   --  Entropy_Budget_Max.

   function Saturating_Add_U64
     (A, B : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is (if B > 0 and then A > Interfaces.Unsigned_64'Last - B
       then Interfaces.Unsigned_64'Last else A + B);

   --  Привилегированный syscall: userspace-демон (в исходной терминологии
   --  «uring 0», см. примечание §13.3 порта) подаёт энтропию в ядро.
   --  Требует мандат с Bind_Prm (только init/entropy-демон имеет такой
   --  мандат).
   generic
      type Object_Type is new Kernel_Object with private;
   procedure Entropy_Feed
     (Caller_Cap : Object_Bind_Prm_Ref;  --  требует Bind_Prm
      Bytes      : Interfaces.Unsigned_64;
      Status     : out Kernel_Error);


end Aura.Entropy;
