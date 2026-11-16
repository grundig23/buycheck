using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;
using BuyCheck;

class GuiTest
{
    static void Snap(Form f, string name, int ms)
    {
        Timer t = new Timer();
        t.Interval = ms;
        t.Tick += delegate {
            t.Stop();
            try {
                using (Bitmap b = new Bitmap(f.Width, f.Height)) {
                    using (Graphics g = Graphics.FromImage(b)) g.CopyFromScreen(f.Location, Point.Empty, f.Size);
                    b.Save("/tmp/bc-build/shots/" + name + ".png", ImageFormat.Png);
                }
                Console.WriteLine("OK " + name + " " + f.Width + "x" + f.Height);
            } catch (Exception ex) { Console.WriteLine("SNAPFAIL " + name + ": " + ex.Message); }
            f.Close();
        };
        f.Shown += delegate { t.Start(); };
        f.ShowDialog();
    }

    [STAThread]
    static void Main()
    {
        Application.EnableVisualStyles();
        // Auswahl
        CheckInfo a = new CheckInfo(); a.Id = "storage.health"; a.Category = "Speicher (SSD/HDD)"; a.CategoryOrder = 3; a.Order = 1; a.Title = "Laufwerks-Gesundheit"; a.Description = "Liest SMART/NVMe-Gesundheitswerte."; a.BaseSeconds = 15; a.Profiles = new string[] { "quick", "thorough" }; a.Selected = true;
        CheckInfo b = new CheckInfo(); b.Id = "cpu.stress"; b.Category = "Prozessor"; b.CategoryOrder = 2; b.Order = 2; b.Title = "Belastungstest"; b.Description = "CPU-Last mit Prüfsummen."; b.BaseSeconds = 20; b.Interactive = true; b.NeedsAcPower = true; b.Profiles = new string[] { "thorough" };
        b.AddOption("minutes", "Dauer", 3, 1, 30, 60, "Minuten");
        ProfileInfo[] p = { new ProfileInfo("quick", "Schnellcheck vor Ort (~25 Min.)", "Die wichtigsten Tests."), new ProfileInfo("thorough", "Gründlich (~75 Min.)", "Alles außer Spezialtests.") };
        SelectionDialog sd = new SelectionDialog(new CheckInfo[] { a, b }, p, "quick", true, "Hinweistext oben.");
        Snap(sd, "selection", 1500);
        Console.WriteLine("Selection profile=" + sd.ProfileId + " a=" + a.Selected + " b=" + b.Selected);
        Snap(new AskDialog("Frage", "Wie war das Bild?", new string[] { "Gut", "Schlecht" }, false, true, "Weiter", null), "ask_choice", 800);
        Snap(new AskDialog("Frage", "Was ist aufgefallen?", new string[] { "Pixel", "Flecken", "Streifen" }, true, true, "Weiter", null), "ask_multi", 800);
        Snap(new KeyboardTestForm(), "keyboard", 1200);
        Snap(new TouchpadTestForm(), "touchpad", 1200);
        Snap(new UsbTestForm(), "usb", 800);
        Snap(new SpeakerTestForm(), "speaker", 800);
        Snap(new MicTestForm("/tmp/bc-build/x.wav"), "mic", 800);
        Snap(new ExternalDisplayForm(), "display", 800);
        Console.WriteLine("online=" + PowerWaitDialog.IsOnline() + " pct=" + PowerWaitDialog.BatteryPercent());
        ChecklistItem[] items = { new ChecklistItem("Gehäuse ohne Risse", "Ecken, Deckel, Unterseite"), new ChecklistItem("Scharniere fest", "") };
        Snap(new ChecklistDialog("Sichtprüfung", "Bitte prüfen:", items), "checklist", 1000);
        Snap(new PixelTestForm(), "pixel", 1000);
        byte[] wav = AudioUtil.MakeWav(44100, 0.5, 440, 440, true, false, 0.5);
        System.IO.File.WriteAllBytes("/tmp/bc-build/t.wav", wav);
        double[] r = AudioUtil.AnalyzeWav("/tmp/bc-build/t.wav");
        Console.WriteLine("WAV peak=" + r[0].ToString("0.0") + " rms=" + r[1].ToString("0.0") + " sec=" + r[2].ToString("0.00"));
        Console.WriteLine("DONE");
    }
}
