using System;
using System.Collections.Generic;
namespace BuyCheck {
    public class CheckOption
    {
        public string Key = "";
        public string Label = "";
        public string Unit = "";
        public decimal Value;
        public decimal Min;
        public decimal Max = 100;
        public decimal Increment = 1;
        public int DecimalPlaces;
        public int SecondsPerUnit;   // wie stark die Option die geschätzte Dauer beeinflusst
    }

    public class CheckInfo
    {
        public string Id = "";
        public string Category = "";
        public int CategoryOrder;
        public int Order;
        public string Title = "";
        public string Description = "";
        public int BaseSeconds;
        public bool Interactive;
        public bool NeedsAcPower;
        public string[] Profiles = new string[0];
        public bool Selected;
        public List<CheckOption> Options = new List<CheckOption>();

        public CheckOption AddOption(string key, string label, decimal value, decimal min, decimal max, int secondsPerUnit, string unit)
        {
            CheckOption o = new CheckOption();
            o.Key = key; o.Label = label; o.Value = value; o.Min = min; o.Max = max;
            o.SecondsPerUnit = secondsPerUnit; o.Unit = unit ?? "";
            Options.Add(o);
            return o;
        }

        public decimal GetOption(string key, decimal fallback)
        {
            foreach (CheckOption o in Options) if (o.Key == key) return o.Value;
            return fallback;
        }

        public void SetOption(string key, decimal value)
        {
            foreach (CheckOption o in Options)
                if (o.Key == key) o.Value = Math.Max(o.Min, Math.Min(o.Max, value));
        }

        public int EstimatedSeconds()
        {
            decimal s = BaseSeconds;
            foreach (CheckOption o in Options) s += o.Value * o.SecondsPerUnit;
            return (int)s;
        }

        public bool InProfile(string profileId)
        {
            if (profileId == "all") return true;
            if (profileId == "none") return false;
            foreach (string p in Profiles) if (p == profileId) return true;
            return false;
        }
    }

    public class ProfileInfo
    {
        public string Id = "";
        public string Label = "";
        public string Description = "";
        public ProfileInfo() { }
        public ProfileInfo(string id, string label, string description) { Id = id; Label = label; Description = description; }
    }

    // Ergebnis eines interaktiven Tests
    public class InteractiveResult
    {
        public string Verdict = "Skip";   // OK | Problem | Skip
        public string Comment = "";
        public List<string> Problems = new List<string>();
        public List<string> Details = new List<string>();
    }

    public class AskResult
    {
        public bool Cancelled = true;
        public int Choice = -1;
        public string ChoiceText = "";
        public bool[] Checked = new bool[0];
        public List<string> CheckedTexts = new List<string>();
        public string Comment = "";
    }


}
