--  AURA Kernel — Secure Bindings
--  Пп.46,47 дорожной карты:
--  46: Construct_Secure_Binding освобождает выделенный объект при
--      ошибках (no memory leak при частичном успехе).
--  47: VA больше не захардкожена как 16#1000_0000# — берётся из
--      аргумента Requested_Va, который передаётся из пространства имён
--      через Binding_Context.
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Vspace;
with Ada.Unchecked_Deallocation;

package body Aura.Secure_Binding is

   use type Interfaces.Unsigned_64;

   function Check_Valid (Cap : Secure_Binding_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap else Ok);

   --  П.46,47 дорожной карты.
   procedure Construct_Secure_Binding
     (Ctx    : Binding_Context;
      Result : out Secure_Binding_Ref;
      Status : out Kernel_Error)
   is
      Sb      : Secure_Binding_Object_Ref;
      Map_St  : Kernel_Error;
   begin
      Result := (Object => null);

      --  Validate inputs.
      if Ctx.Vspace = null then
         Status := Bad_Cap;
         return;
      end if;
      if Ctx.Requested_Va = 0 then
         Status := Invalid_Argument;
         return;
      end if;
      if Ctx.Size = 0 then
         Status := Invalid_Argument;
         return;
      end if;

      --  Аллоцируем объект привязки.
      Sb := new Secure_Binding_Object'
        (Header       => <>,
         Bound_Vspace => Ctx.Vspace,
         Va           => Ctx.Requested_Va,
         Size         => Ctx.Size,
         Flags        => Ctx.Flags,
         Active       => False);

      --  П.47: отображаем по Ctx.Requested_Va (от caller), не по
      --  захардкоженному 16#1000_0000#.
      Aura.Vspace.Vspace_Map
        (Vs     => Ctx.Vspace,
         Va     => Ctx.Requested_Va,
         Phys   => Ctx.Phys_Base,
         Size   => Ctx.Size,
         Flags  => Ctx.Flags,
         Status => Map_St);

      if Map_St /= Ok then
         --  П.46: освобождаем объект при ошибке отображения.
         declare
            procedure Free is new Ada.Unchecked_Deallocation
              (Secure_Binding_Object, Secure_Binding_Object_Ref);
            S : Secure_Binding_Object_Ref := Sb;
         begin
            Free (S);
         end;
         Status := Map_St;
         return;
      end if;

      Sb.Active := True;
      Result    := (Object => Sb);
      Status    := Ok;
   end Construct_Secure_Binding;

   --  П.46: Revoke_Secure_Binding отображает VA и освобождает объект.
   procedure Revoke_Secure_Binding
     (Binding : in out Secure_Binding_Ref;
      Status  : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Binding);
      if Status /= Ok then return; end if;

      if Binding.Object.Active then
         declare
            Unmap_St : Kernel_Error;
         begin
            Aura.Vspace.Vspace_Unmap
              (Vs     => Binding.Object.Bound_Vspace,
               Va     => Binding.Object.Va,
               Size   => Binding.Object.Size,
               Status => Unmap_St);
            pragma Unreferenced (Unmap_St);
         end;
         Binding.Object.Active := False;
      end if;

      declare
         procedure Free is new Ada.Unchecked_Deallocation
           (Secure_Binding_Object, Secure_Binding_Object_Ref);
         S : Secure_Binding_Object_Ref := Binding.Object;
      begin
         Free (S);
      end;
      Binding := (Object => null);
      Status  := Ok;
   end Revoke_Secure_Binding;

end Aura.Secure_Binding;
