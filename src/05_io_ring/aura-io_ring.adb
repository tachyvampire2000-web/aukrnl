--  AURA Kernel — IO Ring (async I/O submission)
--  П.22 дорожной карты: Execute_Step честно возвращает Not_Supported
--  для операций, не реализованных в reference-платформе, вместо
--  безусловного Ok.  Реализованы: Map/Unmap (через Vspace), Attr_Get/Set.
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Vspace;

package body Aura.Io_Ring is

   use type Interfaces.Unsigned_64;

   function Check_Valid (Ring : Io_Ring_Ref) return Kernel_Error is
     (if Ring = null then Bad_Cap else Ok);

   procedure Execute_Step
     (Ring   : Io_Ring_Ref;
      Step   : Io_Ring_Step;
      Status : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Ring);
      if Status /= Ok then return; end if;

      case Step.Op is
         when Read =>
            --  Reference-платформа: реальный disk-I/O отсутствует.
            --  На реальном железе: добавить дескриптор в очередь
            --  DMA-контроллера и ждать completion interrupt.
            Status := Not_Supported;

         when Write =>
            --  Аналогично Read.
            Status := Not_Supported;

         when Map =>
            --  Map реализован через Vspace.Vspace_Map.
            if Ring.Vspace = null then
               Status := Not_Supported;
               return;
            end if;
            Aura.Vspace.Vspace_Map
              (Vs     => Ring.Vspace,
               Va     => Step.Va,
               Phys   => Step.Phys,
               Size   => Step.Size,
               Flags  => Step.Flags,
               Status => Status);

         when Unmap =>
            --  Unmap реализован через Vspace.Vspace_Unmap.
            if Ring.Vspace = null then
               Status := Not_Supported;
               return;
            end if;
            Aura.Vspace.Vspace_Unmap
              (Vs     => Ring.Vspace,
               Va     => Step.Va,
               Size   => Step.Size,
               Status => Status);

         when Attr_Get =>
            --  Возвращает атрибуты текущего отображения по Va.
            if Ring.Vspace = null then
               Status := Not_Supported;
               return;
            end if;
            Aura.Vspace.Vspace_Query_Flags
              (Vs     => Ring.Vspace,
               Va     => Step.Va,
               Flags  => Step.Out_Flags,
               Status => Status);

         when Attr_Set =>
            --  Обновляет флаги уже существующего отображения.
            if Ring.Vspace = null then
               Status := Not_Supported;
               return;
            end if;
            Aura.Vspace.Vspace_Remap_Flags
              (Vs     => Ring.Vspace,
               Va     => Step.Va,
               Size   => Step.Size,
               Flags  => Step.Flags,
               Status => Status);

         when Attr_Watch =>
            --  Мониторинг атрибутов — не реализован в reference-платформе.
            --  На реальном железе: зарегистрировать IOMMU-уведомление или
            --  EPT-violation handler.
            Status := Not_Supported;

         when Mount =>
            --  Namespace-маунт через IO Ring — не реализован.
            --  На реальном железе: вызов Namespace_Mount с параметрами из Step.
            Status := Not_Supported;

         when Device_Query =>
            --  Опрос устройства — не реализован в reference-платформе.
            --  На реальном железе: отправить IOCTL в драйвер.
            Status := Not_Supported;
      end case;
   end Execute_Step;

   procedure Io_Ring_Create
     (Vs     : Aura.Vspace.V_Space_Ref;
      Result : out Io_Ring_Ref;
      Status : out Kernel_Error)
   is
   begin
      Result := new Io_Ring_Object'
        (Header => <>,
         Vspace => Vs,
         Head   => 0,
         Tail   => 0);
      Status := Ok;
   end Io_Ring_Create;

   procedure Io_Ring_Destroy
     (Ring   : in out Io_Ring_Ref;
      Status : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Ring);
      if Status /= Ok then return; end if;
      declare
         procedure Free is new Ada.Unchecked_Deallocation
           (Io_Ring_Object, Io_Ring_Ref);
         R : Io_Ring_Ref := Ring;
      begin
         Free (R);
      end;
      Ring   := null;
      Status := Ok;
   end Io_Ring_Destroy;

end Aura.Io_Ring;
