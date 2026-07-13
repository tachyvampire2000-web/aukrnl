--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

package body Aura.Driver is


   function Check_Valid (Obj : Prm_Resource_Set) return Kernel_Error is (Ok); -- Placeholder
   procedure Hal_Release_Msi_X_Vector (Id : Interfaces.Unsigned_64; Idx : Interfaces.Unsigned_16) is begin null; end;
   procedure Release_All_Resources (Obj : Prm_Resource_Set) is begin null; end;

   type Reincarnation_Contract is record
      Supervised : Process_Context_Ref;
      Respawn_Cap : Erased_Cap;
      Restart_Count : Natural;
      Last_Heartbeat_Tick : Interfaces.Unsigned_64;
   end record;

   procedure Kill_Process (P : Process_Context_Ref; C : Erased_Cap) is begin null; end;
   procedure Respawn_From_Template (P : Process_Context_Ref; C : Erased_Cap; New_P : out Process_Context_Ref) is begin New_P := null; end;
   procedure Rebind_Namespace_Mounts (P : Process_Context_Ref; C : Reincarnation_Contract) is begin null; end;
   procedure Create_Xpc_Endpoint_In_Cspace (P : Process_Context_Ref; E : out Erased_Cap) is begin E := null; end;
   procedure Mint_Prm_Resource_Set_Cap (P : Process_Context_Ref; T : Device_Object; C : out Erased_Cap) is begin C := null; end;
   procedure Mint_Target_Read_Cap (P : Process_Context_Ref; T : Device_Object; C : out Erased_Cap) is begin C := null; end;

   function State (Self : Device_Object) return Device_State is
      Result : constant Device_State_Result :=
        Device_State_From_U8 (Self.State);
   begin
      return (if Result.Ok then Result.Value else Faulted);
   end State;

   procedure Set_State (Self : in out Device_Object; S : Device_State) is
   begin
      Self.State := Device_State'Enum_Rep (S);
   end Set_State;

   procedure Resolve_External_Effect (Self : in out Prm_Resource_Set) is
   begin
      --  T74: при уничтожении освобождаем MSI-X вектора через PRM.
      if (Self.Granted_Classes_Mask and Msi_X_Vector) /= 0 then
         if Self.Msi_X_Vectors.Present then
            for I in Self.Msi_X_Vectors.Vectors'Range loop
               declare
                  V : constant Msi_X_Vector_Desc := Self.Msi_X_Vectors.Vectors(I);
               begin
                  if V.Allocated then
                     Hal_Release_Msi_X_Vector
                       (0, V.Vector_Index); -- Placeholder for Platform_Id
                  end if;
               end;
            end loop;
         end if;
      end if;
      Release_All_Resources (Self);
   end Resolve_External_Effect;

   procedure Prm_Request_Resource
     (Resource_Set      : Prm_Resource_Set;
      Class             : Prm_Resource_Class_Mask;
      Resource_Selector  : Interfaces.Unsigned_64;
      Result            : out Prm_Resource_Cap;
      Status            : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Resource_Set);
      if Status /= Ok then
         return;
      end if;
      if (Resource_Set.Granted_Classes_Mask and Class) = 0 then
         Status := Not_Granted;
         return;
      end if;
      --  OPEN (портировано из todo!() Rust-версии, §18.4): тело не
      --  реализовано ни в Rust-документе, ни здесь.
      Status := Not_Supported;
   end Prm_Request_Resource;

   procedure Rebind_Driver_Caps
     (New_Process : Process_Context_Ref; Target : in out Device_Object);

   procedure Respawn_Driver_Process
     (Target   : in out Device_Object;
      Contract : in out Reincarnation_Contract;
      Now      : Interfaces.Unsigned_64)
   is
      New_Ctx : Process_Context_Ref;
   begin
      --  Переводим устройство в Faulted — запросы в этом окне получат
      --  Driver_Restarting.
      Set_State (Target, Faulted);

      Kill_Process (Contract.Supervised, Contract.Respawn_Cap);
      Respawn_From_Template
        (Contract.Supervised, Contract.Respawn_Cap, New_Ctx);

      --  Шаг 1: восстанавливаем Ns_Mount-записи (общий путь §16.3 порта).
      Rebind_Namespace_Mounts (New_Ctx, Contract);

      --  Шаг 2: восстанавливаем мандаты специфичные для устройства.
      --  Prm_Resource_Set не пересоздаётся — он принадлежит Target, не
      --  процессу. Driver_Endpoint_Cap создаётся заново: старый
      --  Xpc_Endpoint умер вместе со старым процессом.
      Rebind_Driver_Caps (New_Ctx, Target);

      Contract.Supervised := New_Ctx;
      Contract.Restart_Count := Contract.Restart_Count + 1;
      Contract.Last_Heartbeat_Tick := Now;

      --  После успешного respawn — возвращаем в Bound.
      Set_State (Target, Bound);
   end Respawn_Driver_Process;

   procedure Rebind_Driver_Caps
     (New_Process : Process_Context_Ref; Target : in out Device_Object)
   is
      New_Endpoint : Erased_Cap;
      Prm_Cap      : Erased_Cap;
      Target_Cap   : Erased_Cap;
   begin
      --  Создать новый Driver_Endpoint_Cap в CSpace нового процесса (тем
      --  же привилегированным путём, что шаг 7 Driver_Load, §18.3 порта).
      Create_Xpc_Endpoint_In_Cspace (New_Process, New_Endpoint);
      --  Новый мандат на существующий Prm_Resource_Set.
      Mint_Prm_Resource_Set_Cap (New_Process, Target, Prm_Cap);
      --  Мандат на Target с Read (только Io_Op_Device_Query, без Manage).
      Mint_Target_Read_Cap (New_Process, Target, Target_Cap);

      Target.Driver_Endpoint_Cap.all := New_Endpoint;
      Target.Prm_Resource_Set_Cap.all := Prm_Cap;
      --  Target_Cap вложен в CSpace нового процесса на шаге выше —
      --  переменная используется только для того вызова, идентично
      --  Rust `let _ = target_cap;`.
   end Rebind_Driver_Caps;

end Aura.Driver;
