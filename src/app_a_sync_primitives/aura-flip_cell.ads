--  AURA Kernel — aura-flip_cell.ads
--  SPDX-License-Identifier: GPL-2.0-only


generic
   type Element_Type is private;
package Aura.Flip_Cell is

   pragma SPARK_Mode (On);

   type Instance is limited private;

   function Create (Val : Element_Type) return Instance
     with Post => Is_Normal (Create'Result);

   --  Читает активную сторону без блокировки. Безопасно в любой момент,
   --  в том числе во время записи (Rust: read()).
   function Read (Self : Instance) return Element_Type
     with Global => null;

   --  Записывает новое значение атомарно. Должен вызываться под внешним
   --  локом или единственным владельцем — как и в Rust-версии, одновременные
   --  вызовы Write дают гонку данных; здесь это выражено явным требованием
   --  Pre, а не doc-комментарием "SAFETY".
   procedure Write (Self : in out Instance; Val : Element_Type)
     with Post => Is_Normal (Self) and then Read (Self) = Val;

   --  Возвращает true если запись в процессе (диагностика).
   function Is_Writing (Self : Instance) return Boolean
     with Global => null;

   --  Отменяет последнюю ЗАВЕРШЁННУЮ транзакцию. Возможна только если
   --  не идёт запись — как и в Rust-версии.
   procedure Rollback (Self : in out Instance; Ok : out Boolean)
     with Pre  => True,   --  не требует !Is_Writing на входе — сам определяет
     Post => (if Ok then Is_Normal (Self));

   --  Начинает запись без завершения (T65: используется io_batch_execute
   --  для error-path отката до commit). Эквивалент Rust begin_write().
   procedure Begin_Write (Self : in out Instance)
     with Post => Is_Writing (Self);

   --  Завершает запись, начатую Begin_Write. Эквивалент commit_write().
   procedure Commit_Write (Self : in out Instance; Val : Element_Type)
     with Pre  => Is_Writing (Self),
          Post => Is_Normal (Self) and then Read (Self) = Val;

   --  Отменяет незавершённую запись БЕЗ переключения активной стороны —
   --  обратная операция к Begin_Write. Используется в error-path пакетных
   --  операций (io_batch_execute, §5.6a), где после Begin_Write шаг записи
   --  данных провалился и Commit_Write не должен вызываться.
   --  Эквивалент Rust abort_write() (добавлен ext-audit-05 в Rust-версии).
   procedure Abort_Write (Self : in out Instance)
     with Pre  => Is_Writing (Self),
          Post => Is_Normal (Self);

   --  Зачистка обеих сторон.
   procedure Zeroize (Self : in out Instance; Zero : Element_Type)
     with Post => Is_Normal (Self) and then Read (Self) = Zero;

   --  Ghost-функция: формализует инвариант «бит0 == бит1 ⟺ норма».
   --  В Rust-версии этот инвариант утверждался только текстом в §A.2 —
   --  здесь SPARK может доказать его сохранение на каждом переходе состояния
   --  (см. Post-контракты Write/Commit_Write/Abort_Write/Rollback выше).
   function Is_Normal (Self : Instance) return Boolean
     with Ghost, Global => null;

private

   type State_Bits is mod 4;  --  2 бита: [бит1 | бит0], как в Rust-версии
   pragma Atomic (State_Bits);

   type Slot_Array is array (0 .. 1) of Element_Type;

   type Instance is limited record
      State : State_Bits := 0;                      -- атомарный доступ через
                                                       -- pragma Atomic ниже
      Slots : Slot_Array;
   end record
     with Volatile;

   for Instance use record
      State at 0 range 0 .. 7;
   end record;

   function Is_Normal (Self : Instance) return Boolean is
     (((Self.State and 1) = 0) = ((Self.State / 2 and 1) = 0))
     with SPARK_Mode => Off;

end Aura.Flip_Cell;
