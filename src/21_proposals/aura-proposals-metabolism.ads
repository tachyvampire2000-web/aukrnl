--  AURA Kernel — Capability Metabolism proposal
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Object; use Aura.Object;
with Aura.Cap_Node;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Interfaces;
with System;

package Aura.Proposals.Metabolism is

   pragma SPARK_Mode (On);

   --  Capability metabolism links the lifetime of a Capability Node to a
   --  Synapse "wallet". This is a zero-heap real-time lease mechanism
   --  inspired by seL4's time-bounds and biological metabolic principles.

   type Rent_Action_Kind is (Deactivate, Revoke_Permanently);

   type Metabolism_Policy is record
      Wallet_Addr      : System.Address; -- Pointer to Synapse holding charges
      Rent_Per_Tick    : Interfaces.Unsigned_32; -- negative signal applied per tick
      Usage_Reward     : Interfaces.Unsigned_32; -- positive signal applied upon use
      Action           : Rent_Action_Kind;       -- action on threshold underflow
      Lower_Threshold  : Interfaces.Unsigned_32; -- minimum charge before action
   end record;

   type Managed_Cap_Node is limited record
      Header    : Object_Header;
      Cap       : Aura.Cap_Node.Cap_Node_Access;
      Policy    : Metabolism_Policy;
      Is_Active : Boolean;
   end record;

   --  Evaluates a single metabolic tick on the managed capability.
   --  Deducts the rent from the synapse wallet. If the charge drops below
   --  Lower_Threshold, the action (Deactivate/Revoke) is executed on Cap.
   procedure Process_Metabolic_Tick
     (Node   : in out Managed_Cap_Node;
      Status : out Kernel_Error)
     with
       Pre => Node.Cap /= null;

   --  Rewards the capability upon successful usage by feeding a positive charge.
   procedure Reward_Usage
     (Node   : in out Managed_Cap_Node;
      Status : out Kernel_Error)
     with
       Pre => Node.Cap /= null;

end Aura.Proposals.Metabolism;
