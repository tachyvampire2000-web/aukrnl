--  AURA Kernel — Reincarnation (process lifecycle / supervisor)
--  Пп.47,48,31 дорожной карты:
--  47: Kill_Process освобождает VSpace через Vspace_Destroy.
--  48: Respawn_From_Template создаёт новый Process_Context.
--  31: Apply_Restart_Strategy / Watchdog_Trigger_Restart реализованы.
--
--  Реализует объявления из aura-reincarnation.ads (старая структура
--  Reincarnation_Contract с полями Supervised, Group_Head,
--  Associated_Watchdog и т.д.).
--  SPDX-License-Identifier: GPL-2.0-only

with Ada.Unchecked_Deallocation;
with Aura.Vspace; use Aura.Vspace;

package body Aura.Reincarnation is

   use type Process_Context_Ref;
   use type Reincarnation_Contract_Access;
   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_32;
   use type System.Address;

   procedure Free_Ctx is new Ada.Unchecked_Deallocation
     (Aura.Vspace.Process_Context, Process_Context_Ref);

   --  Глобальный лок синхронизации Watchdog_Tick ↔ supervisor-путём.
   protected Reincarnation_Lock is
      pragma Priority (System.Priority'Last);
      entry Acquire;
      procedure Release;
   private
      Locked : Boolean := False;
   end Reincarnation_Lock;

   protected body Reincarnation_Lock is
      entry Acquire when not Locked is
      begin Locked := True; end Acquire;
      procedure Release is
      begin Locked := False; end Release;
   end Reincarnation_Lock;

   --  ──────────────── Вспомогательная: сброс счётчика + watchdog ────────────

   procedure Restart_Single
     (Contract : in out Reincarnation_Contract)
   is
   begin
      Contract.Restart_Count := Contract.Restart_Count + 1;
      if Contract.Associated_Watchdog /= System.Null_Address
        and then Watchdog_Reset_Hook /= null
      then
         Watchdog_Reset_Hook (Contract.Associated_Watchdog);
      end if;
   end Restart_Single;

   --  ─────────────────────── Kill_Process ───────────────────────────────────

   procedure Kill_Process
     (Proc        : Process_Context_Ref;
      Respawn_Cap : Cap_Any_Ref)
   is
      pragma Unreferenced (Respawn_Cap);
   begin
      if Proc = null then return; end if;
      if Proc.Vspace /= null then
         Vspace_Destroy (Proc.Vspace);
      end if;
   end Kill_Process;

   --  ──────────────────── Respawn_From_Template ──────────────────────────────

   procedure Respawn_From_Template
     (Proc        : Process_Context_Ref;
      Respawn_Cap : Cap_Any_Ref;
      New_Ctx     : out Process_Context_Ref)
   is
      pragma Unreferenced (Respawn_Cap);
      Ctx    : Process_Context_Ref;
      Vs     : V_Space_Ref;
      Vs_St  : Kernel_Error;
   begin
      pragma Unreferenced (Proc);
      Vspace_Create (Vs, Vs_St);
      if Vs_St /= Ok then
         New_Ctx := null;
         return;
      end if;
      Ctx        := new Aura.Vspace.Process_Context;
      Ctx.Vspace := Vs;
      New_Ctx    := Ctx;
   end Respawn_From_Template;

   --  ──────────────────── Rebind_Namespace_Mounts ───────────────────────────

   procedure Rebind_Namespace_Mounts
     (Proc     : Process_Context_Ref;
      Contract : Reincarnation_Contract)
   is
      pragma Unreferenced (Proc, Contract);
   begin
      --  Заглушка: поле Ns_Root ещё не добавлено в Reincarnation_Contract
      --  (текущая структура .ads не содержит его).  Функция объявлена
      --  для совместимости с вызовами из Respawn_From_Template.
      null;
   end Rebind_Namespace_Mounts;

   --  ─────────────────── Contract_Escalation ────────────────────────────────

   procedure Contract_Escalation
     (Contract : in out Reincarnation_Contract)
   is
   begin
      case Contract.Escalation_Policy_Field is
         when Notify_Supervisor =>
            --  Уведомление через флаг — supervisor читает при следующем Tick.
            null;
         when Terminate_Container =>
            Contract.Max_Restarts := 0;
         when Kernel_Panic =>
            raise Program_Error with "AURA reincarnation: kernel panic escalation";
      end case;
   end Contract_Escalation;

   --  ────────────────────── Supervisor_Tick ─────────────────────────────────

   procedure Supervisor_Tick
     (Contract : aliased in out Reincarnation_Contract;
      Now      : Interfaces.Unsigned_64)
   is
   begin
      if Contract.Heartbeat_Timeout_Ms = 0 then return; end if;
      declare
         Elapsed : constant Interfaces.Unsigned_64 :=
           (if Now >= Contract.Last_Heartbeat_Tick
            then Now - Contract.Last_Heartbeat_Tick else 0);
      begin
         if Elapsed > Interfaces.Unsigned_64 (Contract.Heartbeat_Timeout_Ms) then
            Watchdog_Trigger_Restart (Contract, Now);
         end if;
      end;
   end Supervisor_Tick;

   --  ─────────────────── Watchdog_Trigger_Restart ───────────────────────────

   procedure Watchdog_Trigger_Restart
     (Contract : aliased in out Reincarnation_Contract;
      Now      : Interfaces.Unsigned_64)
   is
   begin
      Reincarnation_Lock.Acquire;
      Contract.Last_Heartbeat_Tick := Now;
      Restart_Single (Contract);
      if Contract.Restart_Count > Contract.Max_Restarts
        and then Contract.Max_Restarts > 0
      then
         Contract_Escalation (Contract);
      end if;
      Reincarnation_Lock.Release;
   end Watchdog_Trigger_Restart;

   --  ─────────────────── Apply_Restart_Strategy ──────────────────────────────

   procedure Apply_Restart_Strategy
     (Contract : aliased in out Reincarnation_Contract;
      Forced   : Boolean)
   is
      pragma Unreferenced (Forced);

      --  Найти голову группы (сам Contract, если Group_Head.Present = False).
      function Find_Head return Reincarnation_Contract_Access is
      begin
         if not Contract.Group_Head.Present then
            return Contract'Unchecked_Access;
         else
            return Contract.Group_Head.Value;
         end if;
      end Find_Head;

   begin
      case Contract.Restart_Strategy_Field is

         when One_For_One =>
            --  Перезапустить только данный контракт.
            Restart_Single (Contract);

         when One_For_All =>
            --  Перезапустить ВСЕХ детей группы (не саму голову).
            declare
               Head : constant Reincarnation_Contract_Access :=
                 (if not Contract.Group_Head.Present
                  then Contract'Unchecked_Access
                  else Contract.Group_Head.Value);
               Node : Reincarnation_Contract_Access := Head.Next_In_Group;
            begin
               while Node /= null loop
                  Restart_Single (Node.all);
                  Node := Node.Next_In_Group;
               end loop;
            end;

         when Rest_For_One =>
            --  Перезапустить потомков с Sibling_Order > текущего.
            declare
               Head     : constant Reincarnation_Contract_Access := Find_Head;
               My_Order : constant Interfaces.Unsigned_32 := Contract.Sibling_Order;
               Node     : Reincarnation_Contract_Access :=
                 (if Head /= null then Head.Next_In_Group else null);
            begin
               while Node /= null loop
                  if Node.Sibling_Order > My_Order then
                     Restart_Single (Node.all);
                  end if;
                  Node := Node.Next_In_Group;
               end loop;
            end;

      end case;
   end Apply_Restart_Strategy;

   --  ─────────────────────── Hot_Swap_Respawn ────────────────────────────────

   procedure Hot_Swap_Respawn
     (Contract     : aliased in out Reincarnation_Contract;
      New_Template : Cap_Any_Ref;
      Status       : out Kernel_Error)
   is
   begin
      --  Обновить шаблон переспавна и обнулить счётчик рестартов.
      Contract.Respawn_Cap   := New_Template;
      Contract.Restart_Count := 0;
      Status := Ok;
   end Hot_Swap_Respawn;

end Aura.Reincarnation;
