using UnityEngine;

namespace Shatranj.Visual
{
    /// <summary>
    /// Ссылка на PostProcessResources из пакета Post Processing. Лежит в Resources,
    /// поэтому шейдеры пост-обработки попадают в сборку. Создаётся редакторским скриптом.
    /// Поле типа Object — класс компилируется и без пакета.
    /// </summary>
    public class ShoxPostFxRefs : ScriptableObject
    {
        public Object resources;
    }
}
