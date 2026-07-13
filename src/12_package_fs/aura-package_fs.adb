--  Тела OPEN-операций: не реализованы ни в Rust-версии (todo!()), ни
--  здесь — возвращают Not_Supported, не имитируя успех. План
--  реализации перенесён комментариями в спецификацию.

package body Aura.Package_Fs is

   procedure Package_Mount
     (Union  : in out P_Union;
      Image  : Package_Image_Mount_Ref;
      Status : out Kernel_Error)
   is
      pragma Unreferenced (Union, Image);
   begin
      Status := Not_Supported;
   end Package_Mount;

   procedure Package_Unmount
     (Union  : in out P_Union;
      Image  : Package_Image_Mount_Ref;
      Status : out Kernel_Error)
   is
      pragma Unreferenced (Union, Image);
   begin
      Status := Not_Supported;
   end Package_Unmount;

end Aura.Package_Fs;
