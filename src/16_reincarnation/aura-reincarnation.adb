--  AURA Kernel — Reincarnation Contracts implementation
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Reincarnation is

   use type Interfaces.Unsigned_32;

   procedure Kill_Process (Proc : Process_Context_Ref; Respawn_Cap : Cap_Any_Ref) is
      pragma Unreferenced (Proc, Respawn_Cap);
   begin
      --  In reference backend, this is a diagnostic stub/no-op
      null;
   end Kill_Process;

   procedure Respawn_From_Template
     (Proc : Process_Context_Ref; Respawn_Cap : Cap_Any_Ref; New_Ctx : out Process_Context_Ref)
   is
      pragma Unreferenced (Proc, Respawn_Cap);
   begin
      --  Allocate a placeholder process context reference
      New_Ctx := new Integer'(42);
   end Respawn_From_Template;

   procedure Rebind_Namespace_Mounts (Proc : Process_Context_Ref; Contract : Reincarnation_Contract) is
      pragma Unreferenced (Proc, Contract);
   begin
      null;
   end Rebind_Namespace_Mounts;

   procedure Contract_Escalation (Contract : in out Reincarnation_Contract) is
   begin
      -- Escalation actions
      case Contract.Escalation_Policy_Field is
         when Notify_Supervisor =>
            null;
         when Terminate_Container =>
            null;
         when Kernel_Panic =>
            -- Diagnostic panic placeholder under reference backend
            null;
      end case;
   end Contract_Escalation;

   -- Helper to perform restart on a contract in the group
   procedure Restart_Single_Contract (Curr : Reincarnation_Contract_Access; Now : Interfaces.Unsigned_64) is
      New_Ctx : Process_Context_Ref;
   begin
      if Curr /= null then
         Kill_Process (Curr.Supervised, Curr.Respawn_Cap);
         Respawn_From_Template (Curr.Supervised, Curr.Respawn_Cap, New_Ctx);
         Rebind_Namespace_Mounts (New_Ctx, Curr.all);
         Curr.Supervised := New_Ctx;
         Curr.Restart_Count := Curr.Restart_Count + 1;
         Curr.Last_Heartbeat_Tick := Now;
      end if;
   end Restart_Single_Contract;

   procedure Apply_Restart_Strategy (Contract : aliased in out Reincarnation_Contract; Forced : Boolean) is
      pragma Unreferenced (Forced);
      Head : Reincarnation_Contract_Access;
      Curr : Reincarnation_Contract_Access;
   begin
      case Contract.Restart_Strategy_Field is
         when One_For_One =>
            null;

         when One_For_All =>
            -- Find the group head
            if Contract.Group_Head.Present then
               Head := Contract.Group_Head.Value;
            else
               Head := Contract'Unchecked_Access;
            end if;

            -- Restart all contracts in the group except the current one
            Curr := Head;
            while Curr /= null loop
               if Curr /= Contract'Unchecked_Access then
                  Restart_Single_Contract (Curr, Contract.Last_Heartbeat_Tick);
               end if;
               Curr := Curr.Next_In_Group;
            end loop;

         when Rest_For_One =>
            -- Find the group head
            if Contract.Group_Head.Present then
               Head := Contract.Group_Head.Value;
            else
               Head := Contract'Unchecked_Access;
            end if;

            -- Restart contracts with sibling order strictly greater than ours
            Curr := Head;
            while Curr /= null loop
               if Curr /= Contract'Unchecked_Access
                 and then Curr.Sibling_Order > Contract.Sibling_Order
               then
                  Restart_Single_Contract (Curr, Contract.Last_Heartbeat_Tick);
               end if;
               Curr := Curr.Next_In_Group;
            end loop;
      end case;
   end Apply_Restart_Strategy;

   procedure Supervisor_Tick
     (Contract : aliased in out Reincarnation_Contract; Now : Interfaces.Unsigned_64)
   is
      use type Interfaces.Unsigned_64;
      New_Ctx : Process_Context_Ref;
   begin
      if Now - Contract.Last_Heartbeat_Tick
           > Interfaces.Unsigned_64 (Contract.Heartbeat_Timeout_Ms)
      then
         if Contract.Restart_Count >= Contract.Max_Restarts then
            Contract_Escalation (Contract);
            Apply_Restart_Strategy (Contract, Forced => True);
            return;
         end if;

         Kill_Process (Contract.Supervised, Contract.Respawn_Cap);
         Respawn_From_Template
           (Contract.Supervised, Contract.Respawn_Cap, New_Ctx);
         Rebind_Namespace_Mounts (New_Ctx, Contract);
         Contract.Supervised := New_Ctx;
         Contract.Restart_Count := Contract.Restart_Count + 1;
         Contract.Last_Heartbeat_Tick := Now;
         Apply_Restart_Strategy (Contract, Forced => False);
      end if;
   end Supervisor_Tick;

end Aura.Reincarnation;
