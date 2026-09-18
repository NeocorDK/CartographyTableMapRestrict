using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using HarmonyLib;
using System;
using System.Reflection;
using UnityEngine;

[assembly: AssemblyTitle(CartographyTableMapRestrict.BepInExPlugin.pluginName)]
[assembly: AssemblyProduct(CartographyTableMapRestrict.BepInExPlugin.pluginName)]
[assembly: AssemblyVersion(CartographyTableMapRestrict.BepInExPlugin.pluginVersion + ".0")]
[assembly: AssemblyFileVersion(CartographyTableMapRestrict.BepInExPlugin.pluginVersion + ".0")]

namespace CartographyTableMapRestrict
{
    [BepInPlugin(pluginGuid, pluginName, pluginVersion)]
    [BepInProcess("valheim.exe")]
    public class BepInExPlugin : BaseUnityPlugin
    {
        public const string pluginGuid = "aedenthorn.CartographyTableMapRestrict";
        public const string pluginName = "Cartography Table Map Restrict";
        public const string pluginVersion = "0.5.0";

        public static ConfigEntry<bool> modEnabled;
        public static ConfigEntry<bool> hideMinimap;
        public static ConfigEntry<bool> suppressMessage;
        public static ConfigEntry<bool> preventAutoOpen;
        public static ConfigEntry<bool> bypassServerNoMap;
        public static ConfigEntry<bool> isDebug;
        public static ConfigEntry<int> nexusID;

        private static ManualLogSource logger;

        /// <summary>
        /// Set only for the duration of the SetMapMode call that a cartography table triggers.
        /// Every other attempt to switch to the large map is downgraded to the small map.
        /// </summary>
        private static bool openingFromTable;

        public static void Dbgl(string str)
        {
            if (isDebug != null && isDebug.Value && logger != null)
                logger.LogInfo(str);
        }

        public void Awake()
        {
            logger = Logger;

            modEnabled = Config.Bind("General", "Enabled", true, "Enable this mod.");
            hideMinimap = Config.Bind("General", "HideMinimap", true, "Hide the minimap in the corner of the screen.");
            suppressMessage = Config.Bind("General", "SuppressMessage", true, "Suppress the map sync message shown when reading a cartography table.");
            preventAutoOpen = Config.Bind("General", "PreventAutoOpen", true, "Stop the game from force-opening the map when a new location is discovered.");
            bypassServerNoMap = Config.Bind("General", "BypassServerNoMap", true, "Let the cartography table open the map even when the server runs the 'No Map' world modifier.");
            isDebug = Config.Bind("General", "IsDebug", false, "Log what the mod blocks and opens.");
            nexusID = Config.Bind("General", "NexusID", 1739, "Nexus mod ID for updates");

            Harmony.CreateAndPatchAll(Assembly.GetExecutingAssembly(), pluginGuid);
        }

        private static void OpenLargeMap()
        {
            Minimap minimap = Minimap.instance;
            if (minimap == null)
                return;

            // Minimap.SetMapMode clamps every mode to None while Game.m_noMap is set, so the
            // table has to lift that for the duration of the call. Game.UpdateNoMap only runs on
            // spawn and when the world modifiers change, so nothing re-closes the map afterwards.
            bool wasNoMap = Game.m_noMap;
            openingFromTable = true;
            if (bypassServerNoMap.Value)
                Game.m_noMap = false;
            try
            {
                minimap.SetMapMode(Minimap.MapMode.Large);
            }
            finally
            {
                Game.m_noMap = wasNoMap;
                openingFromTable = false;
            }
            Dbgl("Opened the large map from a cartography table.");
        }

        /// <summary>
        /// The one place the game shows the minimap and the only gate into the large map.
        /// </summary>
        [HarmonyPatch(typeof(Minimap), "SetMapMode")]
        public static class Minimap_SetMapMode_Patch
        {
            public static void Prefix(ref Minimap.MapMode mode)
            {
                if (!modEnabled.Value || openingFromTable)
                    return;

                if (mode == Minimap.MapMode.Large)
                {
                    Dbgl("Blocked the large map: not opened from a cartography table.");
                    mode = Minimap.MapMode.Small;
                }
            }

            public static void Postfix(Minimap __instance)
            {
                if (!modEnabled.Value || !hideMinimap.Value)
                    return;

                if (__instance.m_smallRoot != null && __instance.m_smallRoot.activeSelf)
                    __instance.m_smallRoot.SetActive(false);
            }
        }

        /// <summary>
        /// Four-argument overload, also reached from OnWrite. Only touches the sync message.
        /// </summary>
        [HarmonyPatch(typeof(MapTable), "OnRead", new Type[] { typeof(Switch), typeof(Humanoid), typeof(ItemDrop.ItemData), typeof(bool) })]
        public static class MapTable_OnRead_Message_Patch
        {
            public static void Prefix(ref bool showMessage)
            {
                if (!modEnabled.Value)
                    return;

                if (suppressMessage.Value)
                    showMessage = false;
            }
        }

        /// <summary>
        /// Three-argument overload, wired to the table's read switch. Patching this one rather than
        /// the overload it forwards to keeps the map from opening when the table is written to.
        /// </summary>
        [HarmonyPatch(typeof(MapTable), "OnRead", new Type[] { typeof(Switch), typeof(Humanoid), typeof(ItemDrop.ItemData) })]
        public static class MapTable_OnRead_OpenMap_Patch
        {
            public static void Postfix(ItemDrop.ItemData item)
            {
                if (!modEnabled.Value || Player.m_localPlayer == null || item != null)
                    return;

                OpenLargeMap();
            }
        }

        /// <summary>
        /// Called by Minimap.DiscoverLocation, which otherwise throws the large map open
        /// whenever the player finds a boss stone or similar.
        /// </summary>
        [HarmonyPatch(typeof(Minimap), "ShowPointOnMap")]
        public static class Minimap_ShowPointOnMap_Patch
        {
            public static bool Prefix()
            {
                if (!modEnabled.Value || !preventAutoOpen.Value)
                    return true;

                return false;
            }
        }
    }
}
