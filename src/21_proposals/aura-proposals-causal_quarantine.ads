--  AURA Kernel — Causal Quarantine Dynamic MAC proposal
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Object; use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Interfaces;

package Aura.Proposals.Causal_Quarantine is

   pragma SPARK_Mode (On);

   --  Causal Quarantine introduces dynamic, transient MAC labelling policy
   --  propagated down event chains (Causal_Root) rather than static, permanent
   --  namespace node bindings. Highly inspired by HiStar/Asbestos IFC (Information
   --  Flow Control) and Bell-LaPadula model, it allows AURA to temporarily isolate
   --  threads executing untrusted external triggers until the causal chain resolves.

   type Quarantine_Level is (Clean, Low_Risk, High_Risk, Suspicious);

   type Quarantine_Label is record
      Level      : Quarantine_Level;
      Categories : Interfaces.Unsigned_64;
      Valid_Thru : Interfaces.Unsigned_64; -- Timestamp after which quarantine expires
   end record;

   type Causal_Quarantine_Domain is limited record
      Header     : Object_Header;
      Thread_Id  : Interfaces.Unsigned_32;
      Label      : Quarantine_Label;
      Is_Blocked : Boolean;
   end record;

   --  Quarantines a thread domain dynamically based on a causal untrusted trigger.
   procedure Apply_Quarantine
     (Domain     : in out Causal_Quarantine_Domain;
      Level      : Quarantine_Level;
      Categories : Interfaces.Unsigned_64;
      Duration   : Interfaces.Unsigned_64;
      Now        : Interfaces.Unsigned_64);

   --  Propagates quarantine labels from parent to child thread execution contexts.
   procedure Propagate_Quarantine
     (Parent : Causal_Quarantine_Domain;
      Child  : in out Causal_Quarantine_Domain)
     with
       Pre => Parent.Label.Level >= Child.Label.Level;

   --  Checks if a quarantined thread is authorized to perform a write-down operation.
   --  Returns False if it violates Strong Tranquility or Information Flow constraints.
   function Check_Write_Authorized
     (Domain     : Causal_Quarantine_Domain;
      Target_Lvl : Quarantine_Level;
      Now        : Interfaces.Unsigned_64) return Boolean;

end Aura.Proposals.Causal_Quarantine;
