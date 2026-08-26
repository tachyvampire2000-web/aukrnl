--  AURA Kernel — VSpace implementation
--  Референс-платформа не имеет MMU, поэтому Map/Unmap/Remap —
--  преднамеренные минимальные заглушки (возвращают Ok или Not_Supported).
--  Вся логика MMU реализуется в HAL-слое конкретной платформы.
--  Vspace_Create / Vspace_Destroy управляют реальными объектами через
--  Ada Storage_Pools (new / Unchecked_Deallocation).
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Unchecked_Deallocation;
with Aura.Ring; use Aura.Ring;

package body Aura.Vspace is

   use type Page_Flags;
   procedure Free_Vs is new Ada.Unchecked_Deallocation
     (V_Space, V_Space_Ref);

   --  ────────────────────────── lifecycle ───────────────────────────────────

   procedure Vspace_Create
     (Vs     : out V_Space_Ref;
      Status : out Kernel_Error)
   is
   begin
      Vs := new V_Space;
      Vs.Header.Epoch      := 1;
      Vs.Header.Min_Ring   := Ring3;
      Vs.Header.Rcu_Domain := null;
      Vs.Page_Table_Root   := 0;
      Status := Ok;
   end Vspace_Create;

   procedure Vspace_Destroy
     (Vs : in out V_Space_Ref)
   is
   begin
      if Vs /= null then
         --  На реальной платформе здесь TLB-flush + walk-free таблицы
         --  страниц.  На референс-платформе достаточно обнулить корень.
         Vs.Page_Table_Root := 0;
         Free_Vs (Vs);
      end if;
   end Vspace_Destroy;

   --  ────────────────────── mapping operations ──────────────────────────────

   --  Заглушки ниже — ПРЕДНАМЕРЕННЫЕ (см. п.22 дорожной карты,
   --  аналогично HAL-заглушкам: «отсутствие MMU на host = no-op»).

   procedure Vspace_Map
     (Vs     : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
       Phys   : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Flags  : Page_Flags;
      Status : out Kernel_Error)
   is
      pragma Unreferenced (Vs, Va, Phys, Size, Flags);
   begin
      --  Референс-платформа: MMU отсутствует — отображение = no-op.
      Status := Ok;
   end Vspace_Map;

   procedure Vspace_Unmap
     (Vs     : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Status : out Kernel_Error)
   is
      pragma Unreferenced (Vs, Va, Size);
   begin
      Status := Ok;
   end Vspace_Unmap;

   procedure Vspace_Map_Template
     (Vs       : V_Space_Ref;
      Template : V_Space;
      Status   : out Kernel_Error)
   is
      pragma Unreferenced (Template);
   begin
      if Vs = null then
         Status := Bad_Cap;
         return;
      end if;
      --  Референс-платформа: нет MMU — копирование Page_Table_Root
      --  является достаточным скелетом для дальнейшей реализации.
      Vs.Page_Table_Root := Template.Page_Table_Root;
      Status := Ok;
   end Vspace_Map_Template;

   procedure Vspace_Query_Flags
     (Vs     : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
      Flags  : out Page_Flags;
      Status : out Kernel_Error)
   is
      pragma Unreferenced (Vs, Va);
   begin
      --  Референс: нет таблицы страниц — возвращаем «present+writable».
      Flags  := Page_Present or Page_Writable;
      Status := Ok;
   end Vspace_Query_Flags;

   procedure Vspace_Remap_Flags
     (Vs        : V_Space_Ref;
      Va        : Interfaces.Unsigned_64;
      Size      : Interfaces.Unsigned_64;
       Flags     : Page_Flags;
      Status    : out Kernel_Error)
   is
      pragma Unreferenced (Vs, Va, Size, Flags);
   begin
      Status := Ok;
   end Vspace_Remap_Flags;

end Aura.Vspace;
