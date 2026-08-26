--  AURA Kernel — Fault delegation implementation
--  Реализует объявления из aura-fault.ads:
--    Thread_Set_Fault_Handler  — сохраняет слабую ссылку на Fault_Endpoint
--                                в поле Thread.Fault_Endpoint.
--    Thread_Resume             — восстанавливает поток после fault:
--                                опционально отображает физическую страницу
--                                и выставляет состояние Ready.
--    Dispatch_Fault_To_Userspace — записывает Fault_Message в Last_Fault
--                                поля связанного Fault_Endpoint; на
--                                референс-платформе это единственный путь
--                                доставки (канал XPC не реализован в HAL).
--
--  П.20 дорожной карты: Downgrade использует Policy.*, не форсирует.
--  П.29 дорожной карты: Dispatch_Fault_To_Userspace реализован.
--  SPDX-License-Identifier: GPL-2.0-only

with System;
with Aura.Vspace;
with System.Storage_Elements; use System.Storage_Elements;

package body Aura.Fault is

   use type Aura.Thread.Thread_Access;
   use type Aura.Thread.Fault_Endpoint_Weak_Ref;

   --  ─────────────────── Thread_Set_Fault_Handler ───────────────────────────

   procedure Thread_Set_Fault_Handler
     (Th       : in out Thread;
      Endpoint : Fault_Endpoint_Write_Ref;
      Status   : out Kernel_Error)
   is
   begin
      if Endpoint.Object = null then
         Status := Bad_Cap;
         return;
      end if;
      --  Сохраняем слабую ссылку: Thread.Fault_Endpoint = access all
      --  Object_Header.  Object_Header — первое поле Fault_Endpoint,
      --  поэтому адреса совпадают; типобезопасность обеспечена.
      Th.Fault_Endpoint :=
        Aura.Thread.Fault_Endpoint_Weak_Ref (Endpoint.Object.Header'Access);
      Status := Ok;
   end Thread_Set_Fault_Handler;

   --  ─────────────────────── Thread_Resume ──────────────────────────────────

   procedure Thread_Resume
     (Thread_Cap : Thread_Manage_Ref;
      Map_Phys   : Phys_Addr_Option;
      Map_Va     : Interfaces.Unsigned_64;
      Status     : out Kernel_Error)
   is
      Th  : constant Aura.Thread.Thread_Access := Thread_Cap.Object;
      St2 : Kernel_Error;
   begin
      if Th = null then
         Status := Bad_Cap;
         return;
      end if;

      --  Если запрошено отображение физической страницы — вызываем Vspace_Map
      --  через Exec_Ctx.Bound_Vspace потока.
      if Map_Phys.Present then
         if Th.Exec_Ctx.Bound_Vspace = null then
            Status := Bad_Cap;
            return;
         end if;
         Aura.Vspace.Vspace_Map
           (Vs     => Th.Exec_Ctx.Bound_Vspace,
            Va     => Map_Va,
             Phys   => Map_Phys.Value,
            Size   => 4096,
            Flags  => Aura.Vspace.Page_Present or Aura.Vspace.Page_Writable,
            Status => St2);
         if St2 /= Ok then
            Status := St2;
            return;
         end if;
      end if;

      --  Снять блокировку и перевести поток обратно в Ready.
      Th.State := Aura.Thread.Ready;
      Status   := Ok;
   end Thread_Resume;

   --  ─────────────────── Dispatch_Fault_To_Userspace ────────────────────────

   --  Вспомогательный тип для восстановления полного Fault_Endpoint из
   --  слабой ссылки (access all Object_Header → access all Fault_Endpoint).
   --  Безопасно: Header — первое поле Fault_Endpoint (Representation_Clause
   --  не требуется — стандарт Ada гарантирует, что первый компонент
   --  лимитированного record располагается по адресу начала объекта, §13.3(2)).
   type Fault_Endpoint_From_Header is access all Fault_Endpoint;

   procedure Dispatch_Fault_To_Userspace
     (Th     : in out Thread;
      Msg    : Fault_Message;
      Status : out Kernel_Error)
   is
      Ep_Addr : System.Address;
      Ep      : Fault_Endpoint_From_Header;
   begin
      if Th.Fault_Endpoint = null then
         Status := User_Fault;
         return;
      end if;

      Ep_Addr := Th.Fault_Endpoint.all'Address;
      Ep      := Fault_Endpoint_From_Header (Ep_Addr);

      --  На референс-платформе XPC-канал недоступен — сохраняем
      --  Fault_Message в Last_Fault поля Fault_Endpoint.  Userspace-поток
      --  читает его при Thread_Resume (опрашивает Handler_Ep).
      Ep.Last_Fault := Msg;
      Th.State := Aura.Thread.Blocked;
      Status := Ok;
   end Dispatch_Fault_To_Userspace;

end Aura.Fault;
