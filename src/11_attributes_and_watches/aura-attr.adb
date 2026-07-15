--  AURA Kernel — aura-attr.adb
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Wait_Queue;

package body Aura.Attr is

   use type Interfaces.Unsigned_32;
   use type Aura.Notification.Notification_Ref;

   function Downgrade
     (Strong : Notification_Ref) return Notification_Weak_Ref
   is
     (Target         => Strong,
      Expected_Epoch =>
        (if Strong /= null then Strong.Header.Epoch else 0));

   procedure Upgrade
     (Self  : Notification_Weak_Ref;
      Value : out Notification_Ref;
      Alive : out Boolean)
   is
   begin
      if Self.Target /= null
        and then Self.Target.Header.Epoch = Self.Expected_Epoch
      then
         Value := Self.Target;
         Alive := True;
      else
         Value := null;
         Alive := False;
      end if;
   end Upgrade;

   function Check_Valid (Cap : Notification_Write_Ref) return Kernel_Error is
     (if Cap.Object = null then Bad_Cap
      elsif not Contains (Cap.Rights, Write) then Bad_Rights
      else Ok);

   procedure Construct_Attr_Watch
     (Target_Notif     : Notification_Weak_Ref;
      Signal_Bit       : Interfaces.Unsigned_64;
      Path_Pattern     : Name_Strings.Bounded_String;
      Rate_Limit_Ticks : Interfaces.Unsigned_64;
      Result           : out Attr_Watch_Ref)
   is
   begin
      Result := new Attr_Watch'
        (Header           => <>,
         Coalesced_Count   => 0,
         Target_Notif      => Target_Notif,
         Signal_Bit        => Signal_Bit,
         Path_Pattern      => Path_Pattern,
         Rate_Limit_Ticks  => Rate_Limit_Ticks,
         Last_Notify_Tick  => 0,
         Active            => True,
         Next_Subscriber   => null);
   end Construct_Attr_Watch;

   procedure Radix_For_Path
     (Root   : in out Radix_Node_Ref;
      Path   : String;
      Result : out Radix_Node_Ref;
      Status : out Kernel_Error)
   is
      pragma Unreferenced (Path);
   begin
      --  Reference-реализация: один узел на пространство имён;
      --  полноценное radix-дерево путей — открытая задача §11 порта.
      if Root = null then
         Root := new Radix_Node;
      end if;
      Result := Root;
      Status := Ok;
   end Radix_For_Path;

   procedure Radix_Insert_Subscriber
     (Node   : Radix_Node_Ref;
      Watch  : Attr_Watch_Ref;
      Status : out Kernel_Error)
   is
   begin
      if Node = null or else Watch = null then
         Status := Invalid_Argument;
         return;
      end if;
      Watch.Next_Subscriber := Node.Subscribers;
      Node.Subscribers      := Watch;   --  publish-порядок RCU
      Status := Ok;
   end Radix_Insert_Subscriber;

   procedure Sanitize_Fields (Self : in out Attr_Entry) is
      Zero : constant Attr_Value := (Kind => Int64_Kind, Int64_Val => 0);
   begin
      Attr_Value_Cells.Zeroize (Self.Value, Zero);
   end Sanitize_Fields;

   procedure Attr_Watch_Create
     (Node          : Namespace_Node_Ref;
      Path          : String;
      Notif_Cap     : Notification_Write_Ref;
      Signal_Bit    : Interfaces.Unsigned_64;
      Rate_Limit_Ms : Interfaces.Unsigned_32;
      Result        : out Attr_Watch_Ref;
      Status        : out Kernel_Error)
   is
      Radix        : Radix_Node_Ref;
      Radix_Status  : Kernel_Error;
      Insert_Status : Kernel_Error;
   begin
      Status := Check_Valid (Notif_Cap);
      if Status /= Ok then
         return;
      end if;

      Construct_Attr_Watch
        (Target_Notif    => Downgrade (Notif_Cap.Object),
         Signal_Bit      => Signal_Bit,
         Path_Pattern    => Name_Strings.To_Bounded_String (Path),
         Rate_Limit_Ticks => Ms_To_Ticks
           (Interfaces.Unsigned_64 (Rate_Limit_Ms)),
         Result           => Result);

      Radix_For_Path (Node.Attributes, Path, Radix, Radix_Status);
      if Radix_Status /= Ok then
         Status := Radix_Status;
         return;
      end if;

      Radix_Insert_Subscriber (Radix, Result, Insert_Status);
      Status := Insert_Status;
   end Attr_Watch_Create;

   procedure Attr_Unwatch (Watch : in out Attr_Watch) is
   begin
      Watch.Active := False;
   end Attr_Unwatch;

   procedure Notify_Watchers
     (Radix : in out Radix_Node; Now_Tick : Interfaces.Unsigned_64)
   is
      Ptr           : Attr_Watch_Access;
      Watch         : Attr_Watch_Access;
      Last, Limit   : Interfaces.Unsigned_64;
      Notif_Alive   : Boolean;
      Notif         : Notification_Ref;
   begin
      Aura.Rcu.Global_Domain.Read_Lock;

      Ptr := Radix.Subscribers;
      while Ptr /= null loop
         Watch := Ptr;

         if not Watch.Active then
            Ptr := Watch.Next_Subscriber;
            goto Continue;
         end if;

         Last  := Watch.Last_Notify_Tick;
         Limit := Watch.Rate_Limit_Ticks;

         if Saturating_Sub_U64 (Now_Tick, Last) < Limit then
            Watch.Coalesced_Count := Watch.Coalesced_Count + 1;
            Ptr := Watch.Next_Subscriber;
            goto Continue;
         end if;

         Upgrade (Watch.Target_Notif, Notif, Notif_Alive);
         if Notif_Alive then
            Notif.Pending := Notif.Pending or Watch.Signal_Bit;
            if Aura.Wait_Queue.Waiter_Count_Snapshot (Notif.Wait_Queue) > 0
            then
               Aura.Wait_Queue.Wake_All_With_Signal (Notif.Wait_Queue);
            end if;
            Watch.Last_Notify_Tick := Now_Tick;
         end if;

         Ptr := Watch.Next_Subscriber;
         <<Continue>>
         null;
      end loop;

      Aura.Rcu.Global_Domain.Read_Unlock;
   end Notify_Watchers;

end Aura.Attr;
