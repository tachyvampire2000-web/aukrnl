--  AURA Kernel — aura-attr.ads
--  SPDX-License-Identifier: GPL-2.0-only


with System;
with Interfaces;
with Ada.Strings.Bounded;
with Aura.Object;           use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights;           use Aura.Rights;
with Aura.Flip_Cell;
with Aura.Rcu;
with Aura.Notification;

package Aura.Attr is

   pragma SPARK_Mode (Off);

   use type Interfaces.Unsigned_64;

   Attr_Name_Max : constant := 128;

   package Name_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max => Attr_Name_Max);

   --  Стёртая слабая ссылка на объект ядра: адрес + эпоха.
   type Kernel_Object_Weak_Ref is record
      Target         : System.Address := System.Null_Address;
      Expected_Epoch : Interfaces.Unsigned_32 := 0;
   end record;

   subtype Notification_Ref is Aura.Notification.Notification_Ref;

   type Notification_Weak_Ref is record
      Target         : Notification_Ref;
      Expected_Epoch : Interfaces.Unsigned_32 := 0;
   end record;

   function Downgrade
     (Strong : Notification_Ref) return Notification_Weak_Ref;

   procedure Upgrade
     (Self  : Notification_Weak_Ref;
      Value : out Notification_Ref;
      Alive : out Boolean);

   type Notification_Write_Ref is record
      Object : Notification_Ref;
      Rights : Aura.Rights.Mask := Aura.Rights.Write;
   end record;

   function Check_Valid (Cap : Notification_Write_Ref) return Kernel_Error;

   type Attr_Watch;
   type Attr_Watch_Access is access all Attr_Watch;
   subtype Attr_Watch_Ref is Attr_Watch_Access;

   --  Weak_Cap_Epoch — снимок эпохи без живого мандата.
   --  Attr_Entry переживает процесс-владелец.
   type Weak_Cap_Epoch is record
      Object             : Kernel_Object_Weak_Ref;
      Cap_Token          : Interfaces.Unsigned_64;
      Cap_Creation_Epoch : Interfaces.Unsigned_32;
      Obj_Creation_Epoch : Interfaces.Unsigned_32;
   end record;

   type Attr_Value_Kind is (Int64_Kind, Float64_Kind, Blob_Kind);

   type Attr_Value (Kind : Attr_Value_Kind := Int64_Kind) is record
      case Kind is
         when Int64_Kind =>
            Int64_Val : Interfaces.Integer_64;
         when Float64_Kind =>
            Float64_Val : Interfaces.IEEE_Float_64;
         when Blob_Kind =>
            Phys_Offset : Interfaces.Unsigned_64;
            Length      : Interfaces.Unsigned_32;
            Backing     : Weak_Cap_Epoch;   --  снимок вместо живого мандата
      end case;
   end record;

   package Attr_Value_Cells is new Aura.Flip_Cell (Attr_Value);

   type Attr_Entry is limited record
      Name  : Name_Strings.Bounded_String;
      --  Flip_Cell вместо Ticket_Lock (Attr_Value): читатели не берут лок —
      --  атомарное чтение активной стороны. Писатель (единственный, под
      --  внешним локом таблицы атрибутов) вызывает Write. Незавершённая
      --  запись (крэш/паника) не трогает активную сторону.
      Value      : Attr_Value_Cells.Instance;
      Rcu_Defer  : Aura.Rcu.Defer (Aura.Rcu.Global_Domain'Access);
   end record
     with Volatile;

   --  Реализует Sanitize (§1.7.0/T60 порта): зачистка обеих сторон
   --  Flip_Cell при уничтожении.
   procedure Sanitize_Fields (Self : in out Attr_Entry);


   --  (декларации из продолжения-фрагмента, doc-lines 4321-4439,
   --  после первоначального закрытия Aura.Attr — тела того же
   --  фрагмента вынесены в .adb — см. MANIFEST §Находки)
   type Attr_Watch is limited record
      Header            : Object_Header;
      Coalesced_Count    : aliased Interfaces.Unsigned_32;
      Target_Notif       : Notification_Weak_Ref;
      Signal_Bit         : Interfaces.Unsigned_64;
      Path_Pattern       : Name_Strings.Bounded_String;
      Rate_Limit_Ticks   : aliased Interfaces.Unsigned_64;
      Last_Notify_Tick   : aliased Interfaces.Unsigned_64;
      Active             : aliased Boolean;
      Next_Subscriber    : Attr_Watch_Access;
   end record
     with Volatile;

   --  Узел radix-дерева путей атрибутов с intrusive-списком
   --  подписчиков (RCU-читаемым).
   type Radix_Node is limited record
      Header      : Object_Header;
      Subscribers : Attr_Watch_Access;
   end record;

   type Radix_Node_Ref is access all Radix_Node;

   type Namespace_Node is limited record
      Header     : Object_Header;
      Attributes : Radix_Node_Ref;
   end record;

   type Namespace_Node_Ref is access all Namespace_Node;

   --  Найти/создать узел для пути Path.
   procedure Radix_For_Path
     (Root   : in out Radix_Node_Ref;
      Path   : String;
      Result : out Radix_Node_Ref;
      Status : out Kernel_Error);

   --  Вставить подписчика в голову списка узла (publish-порядок RCU).
   procedure Radix_Insert_Subscriber
     (Node   : Radix_Node_Ref;
      Watch  : Attr_Watch_Ref;
      Status : out Kernel_Error);

   Ticks_Per_Ms : constant := 1;

   function Ms_To_Ticks
     (Ms : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is (Ms * Ticks_Per_Ms);

   procedure Attr_Watch_Create
     (Node          : Namespace_Node_Ref;
      Path          : String;
      Notif_Cap     : Notification_Write_Ref;  --  требует Write
      Signal_Bit    : Interfaces.Unsigned_64;
      Rate_Limit_Ms : Interfaces.Unsigned_32;
      Result        : out Attr_Watch_Ref;
      Status        : out Kernel_Error)
   with Pre => Contains (Notif_Cap.Rights, Write);

   procedure Attr_Unwatch (Watch : in out Attr_Watch);

   --  Уведомить всех активных подписчиков узла с rate-limit и
   --  коалесцированием.
   procedure Notify_Watchers
     (Radix : in out Radix_Node; Now_Tick : Interfaces.Unsigned_64);




   function Saturating_Sub_U64
     (A, B : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is (if A >= B then A - B else 0);

end Aura.Attr;
