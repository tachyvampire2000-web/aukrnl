--  AURA Kernel — aura-timer.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Interfaces;

package Aura.Timer is

   pragma SPARK_Mode (Off);

   Timer_Irq : constant := 0;

   use type Interfaces.Unsigned_64;

   Global_Tick : aliased Interfaces.Unsigned_64 := 0;

   Max_Deadline_Timers : constant := 16;

   type Deadline_Timer_Callback is access procedure;

   type Deadline_Timer is record
      Deadline : Interfaces.Unsigned_64 := 0;
      Callback : Deadline_Timer_Callback := null;
      Active   : Boolean := False;
   end record;

   procedure Register_Deadline_Timer
     (Deadline : Interfaces.Unsigned_64;
      Callback : Deadline_Timer_Callback;
      Success  : out Boolean);

   procedure Timer_Interrupt_Handler
   with Export, Convention => C;


   function Current_Tick return Interfaces.Unsigned_64 is (Global_Tick);

end Aura.Timer;
