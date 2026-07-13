--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Interfaces;

package Aura.Tlb_Shootdown is

   pragma SPARK_Mode (On);

   use type Interfaces.Unsigned_64;

   Max_Cpus : constant := 256;  --  платформенно-зависимая константа,
                                  --  соответствует Rust MAX_CPUS

   type Tlb_Shootdown_Slot is record
      Vspace_Root : aliased Interfaces.Unsigned_64 := 0;
      Start_Va    : aliased Interfaces.Unsigned_64 := 0;
      Size        : aliased Interfaces.Unsigned_64 := 0;
      Active      : aliased Boolean := False;
      --  T71: ACK от целевого CPU (каждый слот принадлежит одному CPU).
      Acked       : aliased Boolean := False;
   end record
     with Volatile;

   --  T68: per-CPU массив — каждый CPU имеет свой слот, нет конфликтов.
   --  Доступ к Slots (Cpu) только через запрашивающий (write) и целевой
   --  (read/ack) CPU — внешнее условие, идентичное doc-комментарию
   --  Rust-версии (там же: только SAFETY-комментарий, не проверяемое
   --  компилятором условие; здесь то же самое отсутствие проверки, честно
   --  сохранённое, а не выданное за большую гарантию).
   Pending_Shootdowns : array (0 .. Max_Cpus - 1) of Tlb_Shootdown_Slot;

   --  T71: максимальное число итераций ожидания ACK (~1 мс при 1 ГГц).
   Shootdown_Timeout_Iters : constant := 1_000_000;

   --  T71: деградировавшие CPU — биты выставляются при таймауте shootdown.
   Degraded_Cpus : aliased Interfaces.Unsigned_64 := 0;


   --  Вызывается из IPI ISR на целевом CPU — читает только свой слот.
   procedure Tlb_Shootdown_Handler
   with Export, Convention => C;


   --  T71: проверить деградацию CPU (для supervisor/health monitor).
   function Cpu_Is_Degraded (Cpu : Natural) return Boolean is
     ((Degraded_Cpus and Interfaces.Shift_Left (1, Cpu)) /= 0);

end Aura.Tlb_Shootdown;
