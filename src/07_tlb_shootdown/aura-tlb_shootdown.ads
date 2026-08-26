--  AURA Kernel — TLB Shootdown specification
--  П.41 дорожной карты: добавлен глобальный Shootdown_Lock вокруг пути
--  IPI-рассылка→ожидание ACK для защиты от нескольких одновременных
--  инициаторов, пишущих в один Pending_Shootdowns(Cpu).
--  SPDX-License-Identifier: GPL-2.0-only

with Interfaces;
with System;

package Aura.Tlb_Shootdown is

   pragma SPARK_Mode (On);

   use type Interfaces.Unsigned_64;

   Max_Cpus : constant := 256;

   type Tlb_Shootdown_Slot is record
      Vspace_Root : aliased Interfaces.Unsigned_64 := 0;
      Start_Va    : aliased Interfaces.Unsigned_64 := 0;
      Size        : aliased Interfaces.Unsigned_64 := 0;
      Active      : aliased Boolean := False;
      Acked       : aliased Boolean := False;
   end record
     with Volatile;

   Pending_Shootdowns : array (0 .. Max_Cpus - 1) of Tlb_Shootdown_Slot;

   Shootdown_Timeout_Iters : constant := 1_000_000;

   Degraded_Cpus : aliased Interfaces.Unsigned_64 := 0;

   --  П.41: глобальный лок для сериализации нескольких одновременных
   --  инициаторов shootdown.  Только один путь может выполнять
   --  IPI-рассылка→ожидание ACK в один момент времени.
   protected Shootdown_Lock is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
      entry Acquire;
      procedure Release;
   private
      Locked : Boolean := False;
   end Shootdown_Lock;

   procedure Tlb_Shootdown_Handler
   with Export, Convention => C;

   function Cpu_Is_Degraded (Cpu : Natural) return Boolean is
     ((Degraded_Cpus and Interfaces.Shift_Left (1, Cpu)) /= 0);

end Aura.Tlb_Shootdown;
