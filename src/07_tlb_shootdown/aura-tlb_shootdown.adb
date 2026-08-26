--  AURA Kernel — TLB Shootdown (с глобальным локом, п.41)
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Vspace;           use Aura.Vspace;
with Aura.Hal;              use Aura.Hal;

package body Aura.Tlb_Shootdown is

   --  П.41: взаимное исключение нескольких инициаторов shootdown.
   protected body Shootdown_Lock is
      entry Acquire when not Locked is
      begin
         Locked := True;
      end Acquire;
      procedure Release is
      begin
         Locked := False;
      end Release;
   end Shootdown_Lock;

   procedure Vspace_Unmap
     (Vspace : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
      Target_Mask    : Interfaces.Unsigned_64;
      Timed_Out_Mask : Interfaces.Unsigned_64 := 0;
      Hal_Status     : Kernel_Error;
   begin
      --  П.41: захватываем глобальный лок до начала IPI-рассылки.
      --  Это гарантирует, что два одновременных инициатора не перепишут
      --  друг другу слоты Pending_Shootdowns.
      Shootdown_Lock.Acquire;

      Hal_Unmap_Segment (Vspace.Page_Table_Root, Va, Size, Hal_Status);
      if Hal_Status /= Ok then
         Shootdown_Lock.Release;
         Status := Hal_Status;
         return;
      end if;

      Target_Mask := Hal_Cpus_With_Vspace (Vspace);
      if Target_Mask = 0 then
         Shootdown_Lock.Release;
         Status := Ok;
         return;
      end if;

      for Cpu in 0 .. Max_Cpus - 1 loop
         if (Target_Mask and Interfaces.Shift_Left (1, Cpu)) /= 0 then
            declare
               Slot : Tlb_Shootdown_Slot renames Pending_Shootdowns (Cpu);
            begin
               Slot.Vspace_Root := Vspace.Page_Table_Root;
               Slot.Start_Va    := Va;
               Slot.Size        := Size;
               Slot.Acked       := False;
               Slot.Active      := True;
               Hal_Send_Tlb_Shootdown_Ipi
                 (Interfaces.Unsigned_32 (Cpu));
            end;
         end if;
      end loop;

      for Cpu in 0 .. Max_Cpus - 1 loop
         if (Target_Mask and Interfaces.Shift_Left (1, Cpu)) /= 0 then
            declare
               Slot  : Tlb_Shootdown_Slot renames Pending_Shootdowns (Cpu);
               Iters : Interfaces.Unsigned_64 := 0;
            begin
               while not Slot.Acked loop
                  Spin_Loop_Hint;
                  Iters := Iters + 1;
                  if Iters >= Shootdown_Timeout_Iters then
                     Degraded_Cpus := Degraded_Cpus
                       or Interfaces.Shift_Left (1, Cpu);
                     Timed_Out_Mask := Timed_Out_Mask
                       or Interfaces.Shift_Left (1, Cpu);
                     Slot.Active := False;
                     exit;
                  end if;
               end loop;
            end;
         end if;
      end loop;

      Shootdown_Lock.Release;
      Status := (if Timed_Out_Mask /= 0 then Hardware_Fault else Ok);
   end Vspace_Unmap;

   procedure Tlb_Shootdown_Handler is
      Cpu  : constant Natural := Current_Cpu_Id;
      Slot : Tlb_Shootdown_Slot renames Pending_Shootdowns (Cpu);
   begin
      if not Slot.Active then return; end if;
      Hal_Local_Tlb_Flush (Slot.Start_Va, Slot.Size);
      Slot.Acked  := True;
      Slot.Active := False;
   end Tlb_Shootdown_Handler;

end Aura.Tlb_Shootdown;
