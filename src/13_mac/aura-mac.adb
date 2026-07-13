--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

package body Aura.Mac is

   protected body Audit_Channel is
      procedure dummy is begin null; end;
   end Audit_Channel;

   procedure Set_Mandatory_Label
     (Node : in out Aura.Namespace.Namespace_Node; New_Label : Mandatory_Label;
      Status : out Kernel_Error)
   is
   begin
      Status := Label_Immutable;  --  всегда — метка неизменяема после
                                    --  создания, идентично Rust-версии
   end Set_Mandatory_Label;

end Aura.Mac;
