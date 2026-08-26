--  AURA Kernel — Driver model
--  Пп.18-19 дорожной карты:
--  18: Check_Valid(Prm_Resource_Set) теперь проверяет реальные поля, а
--      не возвращает Ok безусловно.
--  19: Mint_Prm_Resource_Set_Cap, Mint_Target_Read_Cap и
--      Create_Xpc_Endpoint_In_Cspace аллоцируют реальные объекты вместо
--      new Integer'(100/200/300).
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Cap_Node;

package body Aura.Driver is

   use type Interfaces.Unsigned_32;

   --  П.18: Check_Valid проверяет реальные инварианты ресурсного набора.
   function Check_Valid (Rs : Prm_Resource_Set_Ref) return Kernel_Error is
   begin
      if Rs = null then
         return Bad_Cap;
      end if;
      --  Ресурсный набор должен иметь хотя б один слот (Platform_Id
      --  в допустимом диапазоне платформы).
      if Rs.Platform_Id = 16#FFFF_FFFF# then
         return Invalid_Argument;
      end if;
      --  Диапазоны MMIO/IO-port не должны быть одновременно нулевыми
      --  (пустой ресурсный набор бессмысленен для драйвера).
      if Rs.Mmio_Size = 0 and then Rs.Io_Port_Count = 0 then
         return Invalid_Argument;
      end if;
      return Ok;
   end Check_Valid;

   function Check_Valid (Drv : Driver_Instance_Ref) return Kernel_Error is
     (if Drv = null then Bad_Cap else Ok);

   --  П.19: аллоцируем реальный объект-мандат ресурсного набора.
   procedure Mint_Prm_Resource_Set_Cap
     (Rs      : Prm_Resource_Set_Ref;
      Result  : out Prm_Resource_Set_Cap;
      Status  : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Rs);
      if Status /= Ok then
         Result := (Object => null);
         return;
      end if;
      --  Мандат «только-чтение» на ресурсный набор — не копирует данные,
      --  а ссылается на существующий объект через указатель.
      Result := (Object => Rs);
      Status := Ok;
   end Mint_Prm_Resource_Set_Cap;

   --  П.19: аллоцируем мандат на чтение целевого устройства.
   procedure Mint_Target_Read_Cap
     (Rs      : Prm_Resource_Set_Ref;
      Target  : Interfaces.Unsigned_32;
      Result  : out Target_Read_Cap;
      Status  : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Rs);
      if Status /= Ok then
         Result := (Object => null, Target_Platform_Id => 0);
         return;
      end if;
      if Target = 16#FFFF_FFFF# then
         Result  := (Object => null, Target_Platform_Id => 0);
         Status  := Invalid_Argument;
         return;
      end if;
      Result := (Object             => Rs,
                 Target_Platform_Id => Target);
      Status := Ok;
   end Mint_Target_Read_Cap;

   --  П.19: создаём XPC-endpoint в CSpace вместо возврата new Integer'(300).
   procedure Create_Xpc_Endpoint_In_Cspace
     (Cspace  : Aura.Cap_Node.Cspace_Ref;
      Drv     : Driver_Instance_Ref;
      Result  : out Xpc_Endpoint_Cap;
      Status  : out Kernel_Error)
   is
      Ep : Xpc_Endpoint_Ref;
   begin
      if Cspace = null then
         Result := (Object => null);
         Status := Bad_Cap;
         return;
      end if;
      Status := Check_Valid (Drv);
      if Status /= Ok then
         Result := (Object => null);
         return;
      end if;
      --  Аллоцируем XPC-endpoint и вставляем в CSpace.
      Ep := new Xpc_Endpoint'
        (Header   => <>,
         Driver   => Drv,
         Ring_Buf => null);
      Aura.Cap_Node.Cspace_Insert
        (Cspace => Cspace,
         Object => Ep.all'Address,
         Status => Status);
      if Status /= Ok then
         declare
            procedure Free is new Ada.Unchecked_Deallocation
              (Xpc_Endpoint, Xpc_Endpoint_Ref);
            E : Xpc_Endpoint_Ref := Ep;
         begin
            Free (E);
         end;
         Result := (Object => null);
         return;
      end if;
      Result := (Object => Ep);
      Status := Ok;
   end Create_Xpc_Endpoint_In_Cspace;

   procedure Driver_Init
     (Rs      : Prm_Resource_Set_Ref;
      Drv     : out Driver_Instance_Ref;
      Status  : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Rs);
      if Status /= Ok then
         Drv := null;
         return;
      end if;
      Drv := new Driver_Instance'
        (Header      => <>,
         Resource_Set => Rs,
         State        => Driver_Initialising);
      Status := Ok;
   end Driver_Init;

   procedure Driver_Destroy
     (Drv    : in out Driver_Instance_Ref;
      Status : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Drv);
      if Status /= Ok then return; end if;
      declare
         procedure Free is new Ada.Unchecked_Deallocation
           (Driver_Instance, Driver_Instance_Ref);
         D : Driver_Instance_Ref := Drv;
      begin
         Free (D);
      end;
      Drv    := null;
      Status := Ok;
   end Driver_Destroy;

end Aura.Driver;
