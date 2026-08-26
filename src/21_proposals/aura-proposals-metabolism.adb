--  AURA Kernel — Capability metabolism implementation
--  П.49: постоянный отзыв проходит через Cap_Revoke и EBR.
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Proposals.Metabolism is

   use type Interfaces.Integer_32;

   procedure Process_Metabolic_Tick
     (Node   : in out Managed_Cap_Node;
      Status : out Kernel_Error)
   is
      Delta : Interfaces.Integer_32;
      Syn_Status : Kernel_Error;
   begin
      if Node.Cap = null or else Node.Policy.Wallet = null then
         Status := Bad_Cap;
         return;
      end if;

      Delta := -Interfaces.Integer_32 (Node.Policy.Rent_Per_Tick);
      Syn_Status := Aura.Synapse.Synapse_Apply_Delta
        (Node.Policy.Wallet.all, Delta);
      Node.Is_Active := Node.Policy.Wallet.Charge
        >= Node.Policy.Lower_Threshold;

      if not Node.Is_Active
        and then Node.Policy.Action = Revoke_Permanently
      then
         Aura.Cap_Node.Cap_Revoke (Node.Cap, Status);
         if Status = Ok then
            Node.Is_Active := False;
         end if;
      else
         Status := Syn_Status;
      end if;
   end Process_Metabolic_Tick;

   procedure Reward_Usage
     (Node   : in out Managed_Cap_Node;
      Status : out Kernel_Error)
   is
   begin
      if Node.Cap = null or else Node.Policy.Wallet = null then
         Status := Bad_Cap;
         return;
      end if;
      Status := Aura.Synapse.Synapse_Apply_Delta
        (Node.Policy.Wallet.all,
         Interfaces.Integer_32 (Node.Policy.Usage_Reward));
      Node.Is_Active := Node.Policy.Wallet.Charge
        >= Node.Policy.Lower_Threshold;
   end Reward_Usage;

end Aura.Proposals.Metabolism;