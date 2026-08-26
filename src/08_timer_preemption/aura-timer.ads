--  AURA Kernel — aura-timer.ads
--  SPDX-License-Identifier: GPL-2.0-only

with Interfaces;
with System;

package Aura.Timer is

   pragma SPARK_Mode (Off);

   Timer_Irq : constant := 0;

   use type Interfaces.Unsigned_64;

   --  Глобальный счётчик тиков.  Инкрементируется атомарно через
   --  защищённый объект Tick_State (см. .adb) — потолочный приоритет
   --  Interrupt_Priority'Last гарантирует атомарность на однопроцессорной
   --  reference-платформе и защиту от потерянных инкрементов при вызове
   --  Timer_Interrupt_Handler с нескольких CPU (п.4 дорожной карты).
   --  Читается через Current_Tick без лока (Volatile-чтение).
   Global_Tick : aliased Interfaces.Unsigned_64 := 0
     with Volatile, Atomic;

   Max_Deadline_Timers : constant := 16;

   type Deadline_Timer_Callback is access procedure;

   --  Защищённый реестр таймеров — закрывает п.5 дорожной карты
   --  (Timers_List без лока): Register_Deadline_Timer и Fire_Expired
   --  обоюдно исключают друг друга и Timer_Interrupt_Handler через
   --  protected-объект с потолочным приоритетом.
   protected type Timer_Registry is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
      procedure Register
        (Deadline : Interfaces.Unsigned_64;
         Callback : Deadline_Timer_Callback;
         Success  : out Boolean);
      procedure Fire_Expired (Now : Interfaces.Unsigned_64);
   private
      type Slot is record
         Deadline : Interfaces.Unsigned_64 := 0;
         Callback : Deadline_Timer_Callback := null;
         Active   : Boolean := False;
      end record;
      type Slot_Array is array (1 .. Max_Deadline_Timers) of Slot;
      Slots : Slot_Array;
   end Timer_Registry;

   Timers : Timer_Registry;

   --  Регистрирует абсолютный дедлайн-таймер.  Потокобезопасно.
   procedure Register_Deadline_Timer
     (Deadline : Interfaces.Unsigned_64;
      Callback : Deadline_Timer_Callback;
      Success  : out Boolean);

   procedure Timer_Interrupt_Handler
   with Export, Convention => C;

   function Current_Tick return Interfaces.Unsigned_64 is (Global_Tick);

end Aura.Timer;
