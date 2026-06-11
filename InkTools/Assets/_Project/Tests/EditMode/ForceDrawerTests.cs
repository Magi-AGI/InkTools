using System.Collections.Generic;
using NUnit.Framework;
using UnityEngine;
using Magi.InkTools.Simulation;

namespace Magi.InkTools.Tests.EditMode
{
    public class ForceDrawerTests
    {
        [Test]
        public void DrawStroke_NullTarget_DoesNotThrow()
        {
            var drawer = ScriptableObject.CreateInstance<ForceDrawer>();
            var stroke = new List<Vector2> { new(0.5f, 0.5f) };

            Assert.DoesNotThrow(() => drawer.DrawStroke(null, stroke, Vector2.right));

            Object.DestroyImmediate(drawer);
        }

        [Test]
        public void DrawStroke_NullMaterial_DoesNotThrow()
        {
            var drawer = ScriptableObject.CreateInstance<ForceDrawer>();
            var rt = new RenderTexture(4, 4, 0, RenderTextureFormat.ARGBFloat);
            rt.Create();
            var stroke = new List<Vector2> { new(0.5f, 0.5f) };

            // drawMaterial is null by default on a fresh instance
            Assert.DoesNotThrow(() => drawer.DrawStroke(rt, stroke, Vector2.right));

            rt.Release();
            Object.DestroyImmediate(rt);
            Object.DestroyImmediate(drawer);
        }

        [Test]
        public void DrawStroke_EmptyStroke_DoesNotThrow()
        {
            var drawer = ScriptableObject.CreateInstance<ForceDrawer>();
            var rt = new RenderTexture(4, 4, 0, RenderTextureFormat.ARGBFloat);
            rt.Create();

            Assert.DoesNotThrow(() => drawer.DrawStroke(rt, new List<Vector2>(), Vector2.right));

            rt.Release();
            Object.DestroyImmediate(rt);
            Object.DestroyImmediate(drawer);
        }

        [Test]
        public void DrawPoint_NullTarget_DoesNotThrow()
        {
            var drawer = ScriptableObject.CreateInstance<ForceDrawer>();

            Assert.DoesNotThrow(() =>
                drawer.DrawPoint(null, Vector2.one * 0.5f, Vector2.right, 0.05f, 1f, 2f));

            Object.DestroyImmediate(drawer);
        }

        [Test]
        public void DrawPoint_NullMaterial_DoesNotThrow()
        {
            var drawer = ScriptableObject.CreateInstance<ForceDrawer>();
            var rt = new RenderTexture(4, 4, 0, RenderTextureFormat.ARGBFloat);
            rt.Create();

            // drawMaterial is null by default
            Assert.DoesNotThrow(() =>
                drawer.DrawPoint(rt, Vector2.one * 0.5f, Vector2.right, 0.05f, 1f, 2f));

            rt.Release();
            Object.DestroyImmediate(rt);
            Object.DestroyImmediate(drawer);
        }
    }
}
