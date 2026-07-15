--  AURA Kernel — Mandatory Access Control (MAC) specification
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Object; use Aura.Object;
with Aura.Ticket_Lock;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Namespace;
with Interfaces;

package Aura.Mac is

   pragma SPARK_Mode (On);

   type Audit_Ring_Buffer is access all Integer; -- Placeholder
   package Audit_Locks is new Aura.Ticket_Lock (Audit_Ring_Buffer);

   --  Мандатная метка — хранится как атрибут namespace-ноды.
   --  Ядро не интерпретирует — только userspace MAC-сервис.
   type Mandatory_Label is record
      Level      : Interfaces.Unsigned_8;   -- уровень секретности 0–63
      Categories : Interfaces.Unsigned_64;  -- битовая маска категорий
   end record
     with Convention => C;

   --  Допуск процесса — атрибут Process_Context.
   type Clearance is record
      Level      : Interfaces.Unsigned_8;
      Categories : Interfaces.Unsigned_64;
   end record
     with Convention => C;

   --  T54 (Strong Tranquility): Mandatory_Label фиксируется при создании
   --  навсегда. При попытке изменить метку:
   procedure Set_Mandatory_Label
     (Node : in out Aura.Namespace.Namespace_Node; New_Label : Mandatory_Label;
      Status : out Kernel_Error);

   --  Causal Information Flow Control (CIFC)
   type Causal_Taint is record
      Tainted          : Boolean := False;
      Taint_Level      : Interfaces.Unsigned_8 := 0;
      Taint_Categories : Interfaces.Unsigned_64 := 0;
   end record;

   procedure Propagate_Taint (Taint : in out Causal_Taint; Label : Mandatory_Label);
   function Check_Flow (Taint : Causal_Taint; Target : Mandatory_Label) return Kernel_Error;


   --  (продолжение из источника, doc-lines 4848-4855, после
   --  первоначального закрытия Aura.Mac — см. MANIFEST §Находки)

   protected type Audit_Channel is
      procedure dummy;
   private
      Header  : Object_Header;
      Records : Audit_Locks.Instance;
   end Audit_Channel;

end Aura.Mac;
