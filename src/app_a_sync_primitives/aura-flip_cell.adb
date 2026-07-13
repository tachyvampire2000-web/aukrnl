--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива).

package body Aura.Flip_Cell is

   pragma SPARK_Mode (Off);

   function Create (Val : Element_Type) return Instance is
   begin
      return Result : Instance do
         Result.Slots (0) := Val;
         Result.Slots (1) := Val;
         Result.State := 0;
      end return;
   end Create;

   function Read (Self : Instance) return Element_Type is
      --  бит1 определяет активную сторону
      Idx : constant Natural := (if (Self.State / 2 and 1) = 0 then 0 else 1);
   begin
      return Self.Slots (Idx);
   end Read;

   procedure Write (Self : in out Instance; Val : Element_Type) is
      --  Запись в теневую сторону (не бит1)
      Idx : constant Natural := (if (Self.State / 2 and 1) = 0 then 1 else 0);
   begin
      Self.Slots (Idx) := Val;
      --  Атомарно переключаем оба бита:
      --  00 -> 11 (switch to slots(1))
      --  11 -> 00 (switch to slots(0))
      Self.State := (if Self.State = 0 then 3 else 0);
   end Write;

   function Is_Writing (Self : Instance) return Boolean is
     ((Self.State and 1) /= (Self.State / 2 and 1));

   procedure Rollback (Self : in out Instance; Ok : out Boolean) is
   begin
      if Is_Writing (Self) then
         Ok := False;
      else
         --  Откат к предыдущему нормальному состоянию
         Self.State := (if Self.State = 0 then 3 else 0);
         Ok := True;
      end if;
   end Rollback;

   procedure Begin_Write (Self : in out Instance) is
   begin
      --  Инвертируем бит0 относительно бит1
      Self.State := (if Self.State = 0 then 1 -- 00 -> 01 (writing 1)
                     elsif Self.State = 3 then 2 -- 11 -> 10 (writing 0)
                     else Self.State); -- already writing
   end Begin_Write;

   procedure Commit_Write (Self : in out Instance; Val : Element_Type) is
      --  Запись в теневую сторону (определяется по бит1)
      Idx : constant Natural := (if (Self.State / 2 and 1) = 0 then 1 else 0);
   begin
      Self.Slots (Idx) := Val;
      --  Делаем бит1 равным бит0
      Self.State := (if Self.State = 1 then 3 -- 01 -> 11
                     elsif Self.State = 2 then 0 -- 10 -> 00
                     else Self.State);
   end Commit_Write;

   procedure Abort_Write (Self : in out Instance) is
   begin
      --  Возвращаем бит0 к значению бит1
      Self.State := (if Self.State = 1 then 0 -- 01 -> 00
                     elsif Self.State = 2 then 3 -- 10 -> 11
                     else Self.State);
   end Abort_Write;

   procedure Zeroize (Self : in out Instance; Zero : Element_Type) is
   begin
      Self.Slots (0) := Zero;
      Self.Slots (1) := Zero;
      Self.State := 0;
   end Zeroize;

end Aura.Flip_Cell;
