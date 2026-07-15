--  AURA Kernel — aura-slot_map.adb
--  SPDX-License-Identifier: GPL-2.0-only


package body Aura.Slot_Map is

   use type Interfaces.Unsigned_32;

   function Create return Instance is
   begin
      return Result : Instance do
         for I in Result.Slots'Range loop
            Result.Slots (I).Next_Free :=
              (if I + 1 < Capacity then I + 1 else Free_Sentinel);
         end loop;
         Result.Free_Head := 0;
         Result.Has_Free  := Capacity > 0;
      end return;
   end Create;

   procedure Insert
     (Self    : in out Instance;
      Val     : Element_Type;
      Id      : out Slot_Id;
      Success : out Boolean)
   is
      Idx  : Natural;
      Next : Natural;
   begin
      if not Self.Has_Free then
         Success := False;
         Id := (Idx => 0, Gen => 0);  --  значение не используется при Success = False
         return;
      end if;

      Idx  := Self.Free_Head;
      Next := Self.Slots (Idx).Next_Free;
      Self.Has_Free  := Next /= Free_Sentinel;
      Self.Free_Head := (if Self.Has_Free then Next else 0);

      --  wrapping-инкремент поколения — идентично Rust wrapping_add(1)
      Self.Slots (Idx).Gen := Self.Slots (Idx).Gen + 1;
      Self.Slots (Idx).Data     := Val;
      Self.Slots (Idx).Occupied := True;
      Self.Count := Self.Count + 1;

      Id := (Idx => Idx, Gen => Self.Slots (Idx).Gen);
      Success := True;
   end Insert;

   procedure Remove
     (Self  : in out Instance;
      Id    : Slot_Id;
      Val   : out Element_Type;
      Found : out Boolean)
   is
   begin
      if Self.Slots (Id.Idx).Gen /= Id.Gen
        or else not Self.Slots (Id.Idx).Occupied
      then
         Found := False;
         return;
      end if;

      Val := Self.Slots (Id.Idx).Data;
      Self.Slots (Id.Idx).Occupied := False;
      Self.Slots (Id.Idx).Gen := Self.Slots (Id.Idx).Gen + 1;

      --  Вставка освобождённого слота в голову free-list — та же логика,
      --  что fix-001 в Rust-версии: next_free нового пустого слота указывает
      --  на СТАРУЮ голову list'а, а не теряет её.
      Self.Slots (Id.Idx).Next_Free :=
        (if Self.Has_Free then Self.Free_Head else Free_Sentinel);
      Self.Free_Head := Id.Idx;
      Self.Has_Free  := True;

      Self.Count := Self.Count - 1;
      Found := True;
   end Remove;

   function Get (Self : Instance; Id : Slot_Id) return Element_Type is
     (Self.Slots (Id.Idx).Data);

   function Contains (Self : Instance; Id : Slot_Id) return Boolean is
     (Self.Slots (Id.Idx).Gen = Id.Gen and then Self.Slots (Id.Idx).Occupied);

end Aura.Slot_Map;
