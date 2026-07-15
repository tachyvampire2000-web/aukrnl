--  AURA Kernel — Capability Validity specification
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights; use Aura.Rights;
with Interfaces;

generic
package Aura.Capability.Validity is

   pragma SPARK_Mode (Off);

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   type Process_Context_Ref is access all Integer; -- Placeholder

   function Current_Tick return Interfaces.Unsigned_64
     with Global => null;  --  внешняя, платформенно-зависимая (таймер)

   function Check_Valid (Self : Instance) return Kernel_Error
     with Global => null;

   --  Fastpath без обращения к CDT, если эпоха не изменилась (T25, fix-009).
   --  T27: если мандат временный — fastpath проверяет tick напрямую вместо
   --  кэша эпохи (иначе просроченный мандат мог бы пройти по кэшу).
   procedure Check_Valid_Fast
     (Self  : in out Instance;
      Valid : out Boolean)
     with Global => null;

   function Check_Right (Self : Instance; Required : Mask) return Kernel_Error
     with Global => null;

private

   function Check_Valid (Self : Instance) return Kernel_Error is
      (declare
         Obj_Epoch : constant Interfaces.Unsigned_32 :=
           Epoch_Of (Self.Object.all);
         Cap_Epoch : constant Interfaces.Unsigned_32 :=
           Self.Node.Cap_Epoch;
       begin
         (if Self.Node.Creation_Epoch /= Cap_Epoch
             or else Self.Node.Obj_Creation_Epoch /= Obj_Epoch
          then Revoked
          elsif Self.Node.Valid_Until /= 0
                and then Current_Tick < Self.Node.Valid_From
          then Not_Yet_Valid
          elsif Self.Node.Valid_Until /= 0
                and then Current_Tick >= Self.Node.Valid_Until
          then Expired
          else Ok));


   --  (продолжение из источника, doc-lines 1610-1625, после
   --  первоначального закрытия Aura.Capability.Validity — см. MANIFEST §Находки)
   procedure Process_Create
     (Untyped                   : Instance;  --  требует Manage,
                                                --  эквивалент impl HasManage
      Offset                    : Interfaces.Unsigned_64;
      Initial_Cspace_Slot_Bits  : Interfaces.Unsigned_32;
      Result                    : out Process_Context_Ref;  -- Manage-мандат
      Status                    : out Kernel_Error)
   with Pre => Contains (Untyped.Rights, Manage);
   --  OPEN (портировано из todo!() Rust-версии, §1.8): тело не реализовано
   --  ни в Rust-документе, ни здесь. Три шага, зафиксированные в Rust-версии
   --  как план реализации, переносятся как комментарий, а не как код:
   --    1. Проверить границы и разметку через Untyped_Retype (§3.3 порта).
   --    2. Создать пустой CNode + пустой VSpace.
   --    3. Вернуть мандат Manage на Process_Context вызывающему.
   --  Заполнение CSpace — отдельными вызовами Cap_Mint до первого запуска.
end Aura.Capability.Validity;
