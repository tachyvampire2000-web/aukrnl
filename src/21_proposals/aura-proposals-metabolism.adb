--  AURA Kernel — Capability Metabolism implementation
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Proposals.Metabolism is

   procedure Process_Metabolic_Tick
     (Node   : in out Managed_Cap_Node;
      Status : out Kernel_Error)
   is
   begin
      --  Under reference platform, simulate deduction of Rent_Per_Tick from
      --  associated Synapse "wallet". If current wallet charge goes below Lower_Threshold,
      --  we deactivate or revoke the capability.
      if Node.Policy.Wallet_Addr = System.Null_Address then
         Status := Invalid_Argument;
         return;
      end if;

      if Node.Policy.Rent_Per_Tick > 1000 then
         --  Simulate rent threshold underflow
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
   begin
      if Node.Policy.Wallet_Addr = System.Null_Address then
         Status := Invalid_Argument;
         return;
      end if;

      --  Simulate rewarding the synapse wallet on use
      Node.Is_Active := True;
      Status := Ok;
   end Reward_Usage;

end Aura.Proposals.Metabolism;
