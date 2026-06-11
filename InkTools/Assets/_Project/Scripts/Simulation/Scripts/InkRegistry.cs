using System.Collections.Generic;
using UnityEngine;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Lightweight registry for inks (elements) to surface metadata for debug/UI.
    /// Not a runtime authority; reads from ScriptableObjects or config to provide lists.
    /// </summary>
    [CreateAssetMenu(menuName = "InkTools/Simulation/Ink Registry")]
    public class InkRegistry : ScriptableObject
    {
        [SerializeField] private List<InkTypeEntry> inks = new();

        public IReadOnlyList<InkTypeEntry> Inks => inks;

        [System.Serializable]
        public class InkTypeEntry
        {
            public string Identifier;
            public string DisplayName;
            public Color Color = Color.white;
            public float DefaultTemperature = 295.15f;
            public float Viscosity = 0f;
            public float Dissipation = 1f;
            public float PressureWeight = 1f;
            [TextArea] public string Description;
        }
    }
}
