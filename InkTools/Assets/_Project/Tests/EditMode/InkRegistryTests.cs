using NUnit.Framework;
using UnityEngine;
using Magi.InkTools.Simulation;

namespace Magi.InkTools.Tests.EditMode
{
    public class InkRegistryTests
    {
        [Test]
        public void Inks_EmptyByDefault()
        {
            var registry = ScriptableObject.CreateInstance<InkRegistry>();

            Assert.IsNotNull(registry.Inks);
            Assert.AreEqual(0, registry.Inks.Count);

            Object.DestroyImmediate(registry);
        }

        [Test]
        public void Inks_ReturnsReadOnlyList()
        {
            var registry = ScriptableObject.CreateInstance<InkRegistry>();

            // IReadOnlyList should not be castable back to mutable List
            Assert.IsNotNull(registry.Inks);
            Assert.IsInstanceOf<System.Collections.Generic.IReadOnlyList<InkRegistry.InkTypeEntry>>(registry.Inks);

            Object.DestroyImmediate(registry);
        }
    }
}
