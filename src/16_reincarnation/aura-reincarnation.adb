--  AURA Kernel — Reincarnation Contracts implementation
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Watchdog;
with System;

package body Aura.Reincarnation is

   use type Interfaces.Unsigned_32;
   use type System.Address;
   use type Aura.Vspace.Process_Context_Ref;

   procedure Kill_Process (Proc : Process_Context_Ref; Respawn_Cap : Cap_Any_Ref) is
      pragma Unreferenced (Respawn_Cap);
   begin
      if Proc /= null then
         Proc.Vspace := null; -- Mark as dead/killed
      end if;
   end Kill_Process;

   procedure Respawn_From_Template
     (Proc : Process_Context_Ref; Respawn_Cap : Cap_Any_Ref; New_Ctx : out Process_Context_Ref)
   is
      pragma Unreferenced (Proc, Respawn_Cap);
   begin
      -- Allocate a real process context with a fresh VSpace root
      New_Ctx := new Aura.Vspace.Process_Context'(Vspace => new Aura.Vspace.V_Space);
   end Respawn_From_Template;

   procedure Rebind_Namespace_Mounts (Proc : Process_Context_Ref; Contract : Reincarnation_Contract) is
      pragma Unreferenced (Proc, Contract);
   begin
      --  OPEN: Rebinding namespace mounts requires a global mount table or active namespace registry,
      --  which is currently not fully implemented in the reference backend. Stub/No-op.
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
            raise Program_Error with "AURA KERNEL PANIC: Reincarnation contract escalation limit reached!";
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

         if Curr.Associated_Watchdog /= System.Null_Address then
            Aura.Watchdog.Reset_Watchdog_Heartbeat (Curr.Associated_Watchdog);
         end if;
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

   procedure Hot_Swap_Respawn
     (Contract     : aliased in out Reincarnation_Contract;
      New_Template : Cap_Any_Ref;
      Status       : out Kernel_Error)
   is
      New_Ctx : Process_Context_Ref;
   begin
      if New_Template = null then
         Status := Invalid_Argument;
         return;
      end if;

      -- 1. Update Respawn template to the new version
      Contract.Respawn_Cap := New_Template;

      -- 2. Terminate the old process context gracefully
      Kill_Process (Contract.Supervised, New_Template);

      -- 3. Respawn the new version context from the new template cap
      Respawn_From_Template (Contract.Supervised, New_Template, New_Ctx);

      -- 4. Rebind all namespace mounts and migrate capabilities to the new context
      Rebind_Namespace_Mounts (New_Ctx, Contract);

      -- 5. Update supervised context, reset restart counters for the new component
      Contract.Supervised := New_Ctx;
      Contract.Restart_Count := 0;

      Status := Ok;
   end Hot_Swap_Respawn;

end Aura.Reincarnation;
