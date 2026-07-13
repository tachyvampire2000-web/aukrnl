--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

generic
   type Element_Type is private;
package Aura.Option is

   pragma Pure;

   type Instance (Present : Boolean := False) is record
      case Present is
         when True  => Value : Element_Type;
         when False => null;
      end case;
   end record;

end Aura.Option;
