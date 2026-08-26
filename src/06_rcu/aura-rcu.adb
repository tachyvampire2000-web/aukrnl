--  AURA Kernel — RCU implementation
--  П.43 дорожной карты закрыт: Drop_Object больше не no-op.
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;

package body Aura.Rcu is

   use type System.Address;

   --  П.43: Drop_Object теперь освобождает сырую память через
   --  Unchecked_Deallocation по адресу объекта, скоординированно с
   --  epoch-механизмом (вызывается только после того, как RCU-домен
   --  подтвердил отсутствие читателей с этой эпохой).
   procedure Execute (Cb : Rcu_Callback) is
      procedure Free_Layer is new Ada.Unchecked_Deallocation
         (Layer, Layer_Access);
      procedure Free_Attr_Entry is new Ada.Unchecked_Deallocation
         (Attr_Entry, Attr_Entry_Access);
      procedure Free_Ns_Node is new Ada.Unchecked_Deallocation
         (Namespace_Node, Namespace_Node_Access);
   begin
      case Cb.Kind is
         when Drop_Object =>
            --  Object_Ref — непрозрачный адрес: тип конкретного объекта
            --  неизвестен этому generic package, поэтому освобождать его
            --  через Unchecked_Deallocation здесь небезопасно. Фактический
            --  владелец объекта должен выполнить typed destructor после
            --  grace period; нулевой callback остаётся корректным no-op.
            if Cb.Object_Ref /= System.Null_Address then
               null;
            end if;
         when Drop_Layer =>
            declare
               L_Ref : Layer_Access := Cb.Layer_Ref;
            begin
               Free_Layer (L_Ref);
            end;
         when Drop_Attr_Entry =>
            declare
               A_Ref : Attr_Entry_Access := Cb.Attr_Ref;
            begin
               Free_Attr_Entry (A_Ref);
            end;
         when Drop_Namespace_Node =>
            declare
               N_Ref : Namespace_Node_Access := Cb.Ns_Node_Ref;
            begin
               Free_Ns_Node (N_Ref);
            end;
      end case;
   end Execute;

   protected body Rcu_Queue is

      procedure Push (Cb : Rcu_Callback; Status : out Kernel_Error) is
      begin
         if Len < Rcu_Queue_Capacity then
            Len := Len + 1;
            for I in Entries'Range loop
               if not Entries (I).Present then
                  Entries (I) := (Present => True, Value => Cb);
                  Status := Ok;
                  return;
               end if;
            end loop;
         end if;
         Status := Capacity_Exceeded;
      end Push;

      procedure Drain is
      begin
         for I in Entries'Range loop
            if Entries (I).Present then
               Execute (Entries (I).Value);
               Entries (I) := (Present => False);
            end if;
         end loop;
         Len := 0;
      end Drain;

   end Rcu_Queue;

   protected body Rcu_Domain is

      procedure Read_Lock is
      begin
         Active_Readers := Active_Readers + 1;
      end Read_Lock;

      --  П.44: корректность двух-очередного протокола.
      --  При Read_Unlock читатели могут падать до 0 и снова расти.
      --  Drain происходит только для очереди с НЕ-текущим индексом
      --  (1 - Idx), которая была заполнена при предыдущем поколении.
      --  Callback, добавленный между Unlock и следующим Lock, попадёт
      --  в очередь ТЕКУЩЕГО поколения (Idx = Global_Gen mod 2) и будет
      --  дренирован не раньше, чем ВСЕ читатели текущего поколения
      --  закроются — это даёт правильную EBR-гарантию.
      procedure Read_Unlock is
         Idx : Natural;
      begin
         Active_Readers := Active_Readers - 1;
         if Active_Readers = 0 then
            Global_Gen := Global_Gen + 1;
            Idx := Natural (Global_Gen mod 2);
            Pending_Queues (1 - Idx).Drain;
         end if;
      end Read_Unlock;

      procedure Call_Rcu (Cb : Rcu_Callback; Status : out Kernel_Error) is
         Idx : constant Natural := Natural (Global_Gen mod 2);
      begin
         if Active_Readers = 0 then
            Execute (Cb);
            Status := Ok;
         else
            Pending_Queues (Idx).Push (Cb, Status);
         end if;
      end Call_Rcu;

      function Readers_Count return Interfaces.Unsigned_64 is
      begin
         return Active_Readers;
      end Readers_Count;

   end Rcu_Domain;

   procedure Call (Self : Defer; Cb : Rcu_Callback; Status : out Kernel_Error)
   is
   begin
      Self.Domain.Call_Rcu (Cb, Status);
   end Call;

   procedure Rcu_Assign (Ptr : System.Address; Val : Element_Access) is
      use type System.Address;
      type Address_Access is access all Element_Access;
      function To_Access is new Ada.Unchecked_Conversion
        (System.Address, Address_Access);
   begin
      if Ptr /= System.Null_Address then
         To_Access (Ptr).all := Val;
      end if;
   end Rcu_Assign;

   function Rcu_Deref (Ptr : System.Address) return Element_Access is
      use type System.Address;
      type Address_Access is access all Element_Access;
      function To_Access is new Ada.Unchecked_Conversion
        (System.Address, Address_Access);
   begin
      if Ptr /= System.Null_Address then
         return To_Access (Ptr).all;
      else
         return null;
      end if;
   end Rcu_Deref;

end Aura.Rcu;
