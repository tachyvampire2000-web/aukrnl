--  AURA Kernel — Capability Node allocator & CDT Cascade Revocation specification
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Rights;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Notification;
with Interfaces;

package Aura.Cap_Node is

   pragma SPARK_Mode (On);

   type Cap_Node_Inner;
   type Cap_Node_Access is access all Cap_Node_Inner;
   type Cap_Node_Weak_Ref is access all Cap_Node_Inner;
   type Notification_Weak_Ref is access all Aura.Notification.Notification_Object;

   type Cap_Node_Inner is limited record
      Cap_Epoch          : aliased Interfaces.Unsigned_32;  -- [fix-009] u32
      Creation_Epoch      : Interfaces.Unsigned_32;  -- Cap_Epoch при создании
      Obj_Creation_Epoch  : Interfaces.Unsigned_32;  -- Object.Epoch при создании
      Depth               : Interfaces.Unsigned_32;
      Badge               : Interfaces.Unsigned_32;
      Rights_Mask         : Aura.Rights.Mask;
      Revoke_In_Progress  : aliased Boolean := False;  -- атомарный флаг
      Cap_Token           : Interfaces.Unsigned_64;    -- ID для реестра токенов

      Parent              : Cap_Node_Weak_Ref;
      First_Child          : Cap_Node_Access;
      Next_Sibling         : Cap_Node_Access;
      Prev_Sibling         : Cap_Node_Access;  -- O(1) удаление

      --  T27: временное окно (0 = без ограничения)
      Valid_From          : Interfaces.Unsigned_64 := 0;
      Valid_Until         : Interfaces.Unsigned_64 := 0;

      --  T28: полная маска включая deny-биты (bits 16+);
      --  Rights_Mask хранит только grant-биты
      Rights              : Aura.Rights.Mask;

      --  T30: push-уведомление при revoke
      Revoke_Notify        : Notification_Weak_Ref;
   end record
     with Volatile;

   --  Эквивалент Rust CapNodeInner::alloc() — открытый пункт, как и в
   --  Rust-версии (там тело было todo!()). Сигнатура портирована,
   --  реализация (slab-аллокация + регистрация Cap_Token) не додумывается.
   procedure Alloc
     (Obj_Epoch : Interfaces.Unsigned_32;
      Result    : out Cap_Node_Access;
      Status    : out Kernel_Error)
   with
     Post => (if Status = Ok then Result /= null);

   procedure Cap_Revoke
     (Root   : Cap_Node_Access;
      Status : out Kernel_Error);

   procedure Free (Node : Cap_Node_Access);

   --  Epoch-based Reclamation (EBR)
   procedure Enter_Critical_Section (Cpu : Natural);
   procedure Leave_Critical_Section (Cpu : Natural);
   procedure Advance_Epoch_And_Reclaim;
   procedure Retire (Node : Cap_Node_Access);

end Aura.Cap_Node;
