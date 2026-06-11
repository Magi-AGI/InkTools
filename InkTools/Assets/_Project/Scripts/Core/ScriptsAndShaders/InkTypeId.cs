using System;

namespace Magi.InkTools.Simulation
{
    /// <summary>
    /// Ink type indices matching iparticle struct field order.
    /// Use these instead of magic numbers for type-safe channel indexing.
    ///
    /// For HLSL, include InkTypeId.hlsl which defines INK_FIRE, INK_WATER, etc.
    /// </summary>
    public enum InkTypeId
    {
        Fire = 0,
        Water = 1,
        PlantSeeded = 2,
        PlantGrown = 3,
        Steam = 4,
        Glitter = 5,
        BlackBody = 6,
        ElectricitySeeded = 7,
        ElectricityGrown = 8,
        Ice = 9,

        // Color overrides (not typically used as ink types)
        Red = 10,
        Green = 11,
        Blue = 12,
        Alpha = 13,

        Count = 10  // Number of ink channels (excludes color overrides)
    }
}
