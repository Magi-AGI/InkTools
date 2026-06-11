using System.Collections.Generic;
using NUnit.Framework;
using UnityEngine;
using Magi.InkTools.Simulation;

namespace Magi.InkTools.Tests.EditMode
{
    public class FieldDrawerTests
    {
        [Test]
        public void Paint_NullTarget_DoesNotThrow()
        {
            var drawer = ScriptableObject.CreateInstance<FieldDrawer>();
            var uvs = new List<Vector2> { new(0.5f, 0.5f) };

            Assert.DoesNotThrow(() => drawer.Paint(null, uvs));

            Object.DestroyImmediate(drawer);
        }

        [Test]
        public void Paint_NullMaterial_DoesNotThrow()
        {
            var drawer = ScriptableObject.CreateInstance<FieldDrawer>();
            var rt = new RenderTexture(4, 4, 0, RenderTextureFormat.ARGBFloat);
            rt.Create();
            var uvs = new List<Vector2> { new(0.5f, 0.5f) };

            // paintMaterial is null by default on a fresh instance
            Assert.DoesNotThrow(() => drawer.Paint(rt, uvs));

            rt.Release();
            Object.DestroyImmediate(rt);
            Object.DestroyImmediate(drawer);
        }
    }
}
