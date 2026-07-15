--  AURA Kernel — aura-tlb_shootdown.adb
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Vspace;           use Aura.Vspace;
with Aura.Hal;              use Aura.Hal;

package body Aura.Tlb_Shootdown is

   procedure Vspace_Unmap
     (Vspace : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
      Target_Mask   : Interfaces.Unsigned_64;
      Timed_Out_Mask : Interfaces.Unsigned_64 := 0;
      Hal_Status    : Kernel_Error;
   begin
      --  Платформенный вызов, VA/size уже проверены выше — граница
      --  платформы, идентичная unsafe-блоку Rust-версии.
      Hal_Unmap_Segment (Vspace.Page_Table_Root, Va, Size, Hal_Status);
      if Hal_Status /= Ok then
         Status := Hal_Status;
         return;
      end if;

      Target_Mask := Hal_Cpus_With_Vspace (Vspace);
      if Target_Mask = 0 then
         Status := Ok;
         return;
      end if;

      --  Рассылаем IPI каждому целевому CPU, пишем в его личный слот.
      for Cpu in 0 .. Max_Cpus - 1 loop
         if (Target_Mask and Interfaces.Shift_Left (1, Cpu)) /= 0 then
            declare
               Slot : Tlb_Shootdown_Slot renames Pending_Shootdowns (Cpu);
            begin
               Slot.Vspace_Root := Vspace.Page_Table_Root;
               Slot.Start_Va    := Va;
               Slot.Size        := Size;
               Slot.Acked       := False;
               Slot.Active      := True;  --  Release-семантика через
                                            --  Volatile-запись поля
               Hal_Send_Tlb_Shootdown_Ipi (Interfaces.Unsigned_32 (Cpu));
            end;
         end if;
      end loop;

      --  Ждём ACK от каждого CPU с таймаутом (T71).
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
                     --  T71: CPU не ответил — пометить как degraded.
                     Degraded_Cpus := Degraded_Cpus or
                       Interfaces.Shift_Left (1, Cpu);
                     Timed_Out_Mask := Timed_Out_Mask or
                       Interfaces.Shift_Left (1, Cpu);
                     Slot.Active := False;
                     exit;
                  end if;
               end loop;
            end;
         end if;
      end loop;

      Status := (if Timed_Out_Mask /= 0 then Hardware_Fault else Ok);
   end Vspace_Unmap;

   procedure Tlb_Shootdown_Handler is
      Cpu  : constant Natural := Current_Cpu_Id;
      Slot : Tlb_Shootdown_Slot renames Pending_Shootdowns (Cpu);
   begin
      if not Slot.Active then
         return;
      end if;
      --  VA и size опубликованы через Release/Acquire барьер выше —
      --  граница платформы, идентичная unsafe-блоку Rust-версии.
      Hal_Local_Tlb_Flush (Slot.Start_Va, Slot.Size);
      Slot.Acked  := True;
      Slot.Active := False;
   end Tlb_Shootdown_Handler;

end Aura.Tlb_Shootdown;
