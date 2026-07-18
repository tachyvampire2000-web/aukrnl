--  AURA Kernel — Capability Metabolism implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Synapse;
with Interfaces;

package body Aura.Proposals.Metabolism is

   use type Aura.Synapse.Synapse_Ref;
   use type Interfaces.Integer_32;

   procedure Process_Metabolic_Tick
     (Node   : in out Managed_Cap_Node;
      Status : out Kernel_Error)
   is
      Err : Kernel_Error;
   begin
      if Node.Policy.Wallet = null then
         Status := Invalid_Argument;
         return;
      end if;

      -- Deduct rent by applying negative signal (as a negative delta value)
      Err := Aura.Synapse.Synapse_Apply_Delta
        (Node.Policy.Wallet.all, -Interfaces.Integer_32 (Node.Policy.Rent_Per_Tick));

      if Err /= Ok then
         Status := Err;
         return;
      end if;

      -- If current charge goes below Lower_Threshold, we execute the action on Cap
      if Node.Policy.Wallet.all.Charge < Node.Policy.Lower_Threshold then
         Node.Is_Active := False;
         if Node.Policy.Action = Revoke_Permanently then
            Aura.Cap_Node.Free (Node.Cap);
         end if;
      end if;

      Status := Ok;
   end Process_Metabolic_Tick;

   procedure Reward_Usage
     (Node   : in out Managed_Cap_Node;
      Status : out Kernel_Error)
   is
      Err : Kernel_Error;
   begin
      if Node.Policy.Wallet = null then
         Status := Invalid_Argument;
         return;
      end if;

      -- Reward usage by applying positive signal
      Err := Aura.Synapse.Synapse_Apply_Delta
        (Node.Policy.Wallet.all, Interfaces.Integer_32 (Node.Policy.Usage_Reward));

      if Err /= Ok then
         Status := Err;
         return;
      end if;

      Node.Is_Active := True;
      Status := Ok;
   end Reward_Usage;

end Aura.Proposals.Metabolism;
