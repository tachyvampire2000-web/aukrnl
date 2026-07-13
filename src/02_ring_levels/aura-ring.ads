--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

package Aura.Ring is

   pragma Pure;

   type Ring_Level is (Ring0, Ring3);
   --  Ring0 = kernel, Ring3 = userspace — идентично комментарию
   --  Rust-версии после revert-ring-001.

   for Ring_Level use (Ring0 => 0, Ring3 => 3);  --  сохраняет числовые
                                                    --  значения аппаратных CPL

end Aura.Ring;
