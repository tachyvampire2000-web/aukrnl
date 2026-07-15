--  AURA Kernel — Namespaces specification
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Slot_Map;
with Ada.Strings.Bounded;
with Interfaces;

package Aura.Namespace is

   pragma SPARK_Mode (On);

   type Cap_Any_Ref is access all Integer; -- Placeholder
   type Namespace_Node_Inner;
   type Namespace_Node_Access is access all Namespace_Node_Inner;
   type Namespace_Node_Weak_Ref is access all Namespace_Node_Inner; -- Placeholder
   type Attr_Table is access all Integer; -- Placeholder

   type P_Union_Ref is access all Integer; -- Placeholder
   type Device_Object_Ref is access all Integer; -- Placeholder

   package Slot_Map_Placeholder is new Aura.Slot_Map (Integer);
   subtype Slot_Id is Slot_Map_Placeholder.Slot_Id;

   Namespace_Name_Max : constant := 255;  --  предел для Bounded_String,
                                            --  заменяющего Box<str>

   package Name_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Namespace_Name_Max);

   type Namespace_Node_Inner is limited record
      Header         : Object_Header;
      Associated     : Cap_Any_Ref;         --  эквивалент Option<AnyCapRef>;
                                              --  null-состояние = None
      Parent          : Namespace_Node_Weak_Ref;
      First_Child     : Namespace_Node_Access;
      Next_Sibling    : Namespace_Node_Access;
      Union_Target    : Namespace_Node_Access; --  A_Union (AUFS-подобное объединение слоев Im)
      Union_Priority  : Interfaces.Unsigned_32;
      Is_Union        : Boolean;
      Attributes      : Attr_Table;
      Name            : Name_Strings.Bounded_String;
      -- MAC Mandatory Label fields
      Mac_Level      : Interfaces.Unsigned_8 := 0;
      Mac_Categories : Interfaces.Unsigned_64 := 0;
      Mac_Label_Set  : Boolean := False;
   end record;

   subtype Namespace_Node is Namespace_Node_Inner;


   --  (продолжение из источника, doc-lines 2015-2062, после
   --  первоначального закрытия Aura.Namespace — см. MANIFEST §Находки)
   type Layer_Kind is (System, User, Mount, Container, Service);
   --  System (C): P_Union нескольких пакетов (Haiku-стиль, без приоритета).
   --  User (D): обычная директория в Re, без union.
   --  Mount (E): прямой доступ к физическому/блочному устройству.
   --  Container (F): P_Union образа контейнера (Haiku-стиль).
   --  Service (G): runtime-пространство демона (обычная директория).

   function Letter (Kind : Layer_Kind) return Character is
     (case Kind is
        when System    => 'C',
        when User      => 'D',
        when Mount     => 'E',
        when Container => 'F',
        when Service   => 'G');

   type Layer_State is (Live, Detached);

   type Layer_Backend_Kind is (Package_Backend, Raw_Device_Backend,
                                 Plain_Directory_Backend);

   --  Ada discriminated record — эквивалент Rust enum с данными
   --  (Package(P_Union) | RawDevice(Arc<DeviceObject>) | PlainDirectory(...)).
   type Layer_Backend (Kind : Layer_Backend_Kind := Plain_Directory_Backend) is
     record
        case Kind is
           when Package_Backend =>
              Union : P_Union_Ref;         -- §12 порта
           when Raw_Device_Backend =>
              Device : Device_Object_Ref;
           when Plain_Directory_Backend =>
              Directory : Namespace_Node_Access;
        end case;
     end record;

   Package_Union_Max : constant := 16;

   type Layer is limited record
      Header          : Object_Header;
      Kind            : Layer_Kind;
      Id              : Name_Strings.Bounded_String;
      Slot            : Slot_Id;   --  переиспользуется через generation,
                                     --  как Aura.Slot_Map (§A.4 порта)
      State           : aliased Layer_State;
      Backend         : Layer_Backend;
   end record
     with Volatile;

end Aura.Namespace;
