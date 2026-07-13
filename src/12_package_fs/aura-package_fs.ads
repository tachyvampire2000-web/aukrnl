--  Материализовано из технической спецификации порта ядра AURA на
--  Ada/SPARK (см. MANIFEST.md в корне архива). Это транскрипция кода из
--  спецификации, а не проверенный компилятором результат: известные
--  пробелы (T-Ada-01..10) сохранены как есть, а не восполнены.

with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Interfaces;

package Aura.Package_Fs is

   pragma SPARK_Mode (On);

   Package_Union_Max : constant := 16;

   Path_Bloom_Filter_Words : constant := 32;

   type Bloom_Words is array (0 .. Path_Bloom_Filter_Words - 1)
     of Interfaces.Unsigned_64;

   type Package_Image_Object is record
      Id    : Interfaces.Unsigned_32;
      Bloom : Bloom_Words := [others => 0];
   end record;

   type Package_Image_Ref is access all Package_Image_Object;
   type Package_Image_Mount_Ref is access all Package_Image_Object;

   type Package_Metadata_Layer_C is record
      Bloom : Bloom_Words;
   end record;

   type Union_Bloom_Container is record
      Combined : Bloom_Words;
   end record;
   type Package_Image_Array is array (1 .. Package_Union_Max)
     of Package_Image_Ref;

   type P_Union is limited record
      --  Без приоритета — порядок в массиве не участвует в разрешении
      --  путей, только в порядке итерации/диагностике.
      Images         : Package_Image_Array;
      Image_Count    : Natural range 0 .. Package_Union_Max;
      --  Совмещённый Bloom двух и более пакетов — быстрый отказ при
      --  поиске потенциального конфликта путей на этапе вставки.
      Combined_Bloom : Union_Bloom_Container;
   end record
     with Volatile;
   procedure Package_Mount
     (Union  : in out P_Union;
      Image  : Package_Image_Mount_Ref;  --  требует Mount
      Status : out Kernel_Error);
   --  OPEN (портировано из todo!() Rust-версии, §12.3): тело не
   --  реализовано ни в Rust-документе, ни здесь. Пять шагов плана
   --  переносятся как комментарий:
   --    1. Читать Слой A синхронно.
   --    2. Проверить Слой C (Combined_Bloom) на возможный конфликт путей
   --       с уже смонтированными пакетами; при совпадении — дотест
   --       Hash-Trie по точному пути (бит блума мог дать ложное
   --       совпадение).
   --    3. Если найден РЕАЛЬНЫЙ конфликт пути с другим пакетом в
   --       P_Union — отказ Already_Exists. Никакого priority, который
   --       мог бы "разрешить" конфликт в пользу одного из пакетов: два
   --       пакета, претендующих на один путь, — ошибка установки, а не
   --       повод выбирать победителя.
   --    4. Создать заглушки union-узлов для нового пакета, влить в общее
   --       плоское дерево P_Union.
   --    5. Обновить Combined_Bloom добавлением Слоя C нового пакета.

   --  Обратная операция: убрать пакет из P_Union (например, при удалении
   --  ПО).
   procedure Package_Unmount
     (Union  : in out P_Union;
      Image  : Package_Image_Mount_Ref;
      Status : out Kernel_Error);
   --  OPEN (портировано из todo!() Rust-версии, §12.3): тело не
   --  реализовано. Удалить узлы пакета из дерева; Combined_Bloom можно
   --  оставить консервативно widened (ложные срабатывания не страшны —
   --  это только быстрый отказ перед точной проверкой) либо перестроить
   --  полностью из оставшихся пакетов.

end Aura.Package_Fs;
