// BuyCheck – Bedienoberfläche (Windows Forms). C# 5 / .NET Framework 4.x.
// Alle Fenster lesen nur Eingaben/Systemzustände. Es werden KEINE Einstellungen des Laptops verändert
// (keine Lautstärke-, Anzeige-, Energie- oder sonstigen Systemeinstellungen).

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

namespace BuyCheck
{
    // ================================================================== Datenmodell für die Testauswahl
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

    // ================================================================== Gemeinsame Hilfen
    public static class Ui
    {
        public static readonly Color Green = Color.FromArgb(31, 136, 61);
        public static readonly Color PressedGreen = Color.FromArgb(46, 160, 67);
        public static readonly Color LightGreen = Color.FromArgb(218, 251, 225);
        public static readonly Color Red = Color.FromArgb(207, 34, 46);
        public static readonly Color Orange = Color.FromArgb(154, 103, 0);
        public static readonly Color Blue = Color.FromArgb(9, 105, 218);
        public static readonly Color Gray = Color.FromArgb(87, 96, 106);
        public static readonly Color KeyGray = Color.FromArgb(230, 234, 239);
        public static readonly Color PanelGray = Color.FromArgb(246, 248, 250);

        static Font baseFont, boldFont, titleFont, smallFont;
        public static Font BaseFont { get { if (baseFont == null) baseFont = new Font("Segoe UI", 10F); return baseFont; } }
        public static Font BoldFont { get { if (boldFont == null) boldFont = new Font("Segoe UI", 10F, FontStyle.Bold); return boldFont; } }
        public static Font TitleFont { get { if (titleFont == null) titleFont = new Font("Segoe UI", 14F, FontStyle.Bold); return titleFont; } }
        public static Font SmallFont { get { if (smallFont == null) smallFont = new Font("Segoe UI", 9F); return smallFont; } }

        public static void Init(Form f, string title, int width, int height)
        {
            f.SuspendLayout();
            f.AutoScaleDimensions = new SizeF(96F, 96F);
            f.AutoScaleMode = AutoScaleMode.Dpi;
            f.Font = BaseFont;
            f.Text = title;
            f.StartPosition = FormStartPosition.CenterScreen;
            f.ClientSize = new Size(width, height);
            f.ShowIcon = false;
            f.MinimizeBox = false;
            f.BackColor = Color.White;
            f.TopMost = true;   // sonst verschwinden Dialoge gern hinter dem Konsolenfenster
        }

        public static Label Wrap(string text, int maxWidth, Font font, Color color)
        {
            Label l = new Label();
            l.Text = text ?? "";
            l.AutoSize = true;
            l.MaximumSize = new Size(maxWidth, 0);
            l.Font = font ?? BaseFont;
            l.ForeColor = color.IsEmpty ? Color.Black : color;
            l.Margin = new Padding(3, 3, 3, 8);
            return l;
        }

        public static Button Btn(string text, EventHandler click)
        {
            Button b = new Button();
            b.Text = text;
            b.AutoSize = true;
            b.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            b.Padding = new Padding(10, 3, 10, 3);
            b.Margin = new Padding(6, 6, 6, 6);
            b.UseVisualStyleBackColor = true;
            if (click != null) b.Click += click;
            return b;
        }

        public static string Duration(int seconds)
        {
            if (seconds <= 0) return "–";
            if (seconds < 60) return "< 1 Min.";
            int m = (int)Math.Round(seconds / 60.0);
            if (m < 60) return "ca. " + m + " Min.";
            return "ca. " + (m / 60) + " Std. " + (m % 60) + " Min.";
        }

        // Höhe eines umbrechenden Labels mit fester Breite berechnen (für angedockte Labels)
        public static void FitHeight(Label l, int width)
        {
            if (width < 50) return;
            Size s = TextRenderer.MeasureText(l.Text, l.Font, new Size(width - l.Padding.Horizontal, 0), TextFormatFlags.WordBreak);
            l.Height = s.Height + l.Padding.Vertical + 4;
        }
    }

    // ================================================================== Testauswahl
    public class NoDblClickTreeView : TreeView
    {
        // Doppelklick auf Kontrollkästchen bringt den TreeView-Status durcheinander (bekannter WinForms-Fehler)
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0203) { m.Result = IntPtr.Zero; return; }
            base.WndProc(ref m);
        }
    }

    public class SelectionDialog : Form
    {
        readonly List<CheckInfo> checks;
        readonly List<ProfileInfo> profiles;
        readonly NoDblClickTreeView tree;
        readonly ComboBox profileBox;
        readonly Label profileDesc;
        readonly Label totalLabel;
        readonly Label detailTitle;
        readonly Label detailText;
        readonly FlowLayoutPanel optionPanel;
        readonly CheckBox rememberBox;
        readonly SplitContainer split;
        bool updating;

        public string ProfileId = "custom";
        public bool RememberSelection { get { return rememberBox.Checked; } }

        public SelectionDialog(CheckInfo[] checkArray, ProfileInfo[] profileArray, string profileId, bool remember, string headerInfo)
        {
            checks = new List<CheckInfo>(checkArray);
            profiles = new List<ProfileInfo>(profileArray);
            Ui.Init(this, "BuyCheck – Auswahl der Tests", 1060, 720);
            MinimumSize = new Size(820, 560);

            // Kopfbereich
            Panel header = new Panel();
            header.Dock = DockStyle.Top;
            header.Height = 126;
            header.BackColor = Ui.PanelGray;
            Label title = new Label();
            title.Text = "Was soll geprüft werden?";
            title.Font = Ui.TitleFont;
            title.AutoSize = true;
            title.Location = new Point(16, 10);
            Label sub = new Label();
            sub.Text = headerInfo ?? "";
            sub.AutoSize = true;
            sub.MaximumSize = new Size(1020, 0);
            sub.ForeColor = Ui.Gray;
            sub.Location = new Point(18, 42);
            Label pl = new Label();
            pl.Text = "Voreinstellung:";
            pl.AutoSize = true;
            pl.Location = new Point(18, 90);
            profileBox = new ComboBox();
            profileBox.DropDownStyle = ComboBoxStyle.DropDownList;
            profileBox.Location = new Point(130, 86);
            profileBox.Width = 380;
            foreach (ProfileInfo p in profiles) profileBox.Items.Add(p.Label);
            profileBox.Items.Add("Benutzerdefiniert");
            profileDesc = new Label();
            profileDesc.AutoSize = true;
            profileDesc.MaximumSize = new Size(500, 0);
            profileDesc.ForeColor = Ui.Gray;
            profileDesc.Font = Ui.SmallFont;
            profileDesc.Location = new Point(522, 82);
            header.Controls.Add(title);
            header.Controls.Add(sub);
            header.Controls.Add(pl);
            header.Controls.Add(profileBox);
            header.Controls.Add(profileDesc);

            // Fußbereich (Tabellen-Layout: links Infos, rechts Buttons – keine Überlappung möglich)
            TableLayoutPanel bottom = new TableLayoutPanel();
            bottom.Dock = DockStyle.Bottom;
            bottom.AutoSize = true;
            bottom.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bottom.BackColor = Ui.PanelGray;
            bottom.Padding = new Padding(10, 8, 10, 8);
            bottom.ColumnCount = 2;
            bottom.RowCount = 2;
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            totalLabel = new Label();
            totalLabel.AutoSize = true;
            totalLabel.Font = Ui.BoldFont;
            totalLabel.Margin = new Padding(6, 8, 3, 3);
            rememberBox = new CheckBox();
            rememberBox.Text = "Auswahl für das nächste Mal merken (wird auf dem USB-Stick gespeichert)";
            rememberBox.AutoSize = true;
            rememberBox.Checked = remember;
            rememberBox.Margin = new Padding(8, 6, 3, 3);
            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.AutoSize = true;
            buttons.WrapContents = false;
            buttons.Margin = new Padding(0);
            Button start = Ui.Btn("Start  ▶", OnStart);
            start.Font = Ui.BoldFont;
            Button cancel = Ui.Btn("Abbrechen", delegate { DialogResult = DialogResult.Cancel; Close(); });
            Button none = Ui.Btn("Keine", delegate { ApplyProfile("none"); SelectProfileEntry("none"); });
            Button all = Ui.Btn("Alle", delegate { ApplyProfile("all"); SelectProfileEntry("all"); });
            buttons.Controls.Add(start);
            buttons.Controls.Add(cancel);
            buttons.Controls.Add(none);
            buttons.Controls.Add(all);
            bottom.Controls.Add(totalLabel, 0, 0);
            bottom.Controls.Add(rememberBox, 0, 1);
            bottom.Controls.Add(buttons, 1, 0);
            bottom.SetRowSpan(buttons, 2);
            AcceptButton = start;
            CancelButton = cancel;

            // Mitte: Baum + Details
            split = new SplitContainer();
            split.Dock = DockStyle.Fill;
            split.Orientation = Orientation.Vertical;
            tree = new NoDblClickTreeView();
            tree.CheckBoxes = true;
            tree.Dock = DockStyle.Fill;
            tree.HideSelection = false;
            tree.FullRowSelect = true;
            tree.ShowLines = true;
            tree.ItemHeight = 26;
            tree.BorderStyle = BorderStyle.None;
            tree.AfterCheck += OnAfterCheck;
            tree.AfterSelect += delegate(object s, TreeViewEventArgs e) { ShowDetails(e.Node); };
            split.Panel1.Controls.Add(tree);
            split.Panel1.Padding = new Padding(8);

            Panel detail = new Panel();
            detail.Dock = DockStyle.Fill;
            detail.Padding = new Padding(14, 10, 14, 10);
            detail.AutoScroll = true;
            detailTitle = new Label();
            detailTitle.Font = Ui.BoldFont;
            detailTitle.AutoSize = true;
            detailTitle.Location = new Point(14, 12);
            detailText = new Label();
            detailText.AutoSize = true;
            detailText.Location = new Point(14, 40);
            optionPanel = new FlowLayoutPanel();
            optionPanel.FlowDirection = FlowDirection.TopDown;
            optionPanel.WrapContents = false;
            optionPanel.AutoSize = true;
            detail.Controls.Add(detailTitle);
            detail.Controls.Add(detailText);
            detail.Controls.Add(optionPanel);
            detail.Resize += delegate { LayoutDetails(detail); };
            split.Panel2.Controls.Add(detail);

            Controls.Add(split);
            Controls.Add(bottom);
            Controls.Add(header);

            BuildTree();
            int idx = profiles.FindIndex(delegate(ProfileInfo p) { return p.Id == profileId; });
            updating = true;
            profileBox.SelectedIndex = idx >= 0 ? idx : profiles.Count;
            updating = false;
            ProfileId = idx >= 0 ? profileId : "custom";
            UpdateProfileDesc();
            profileBox.SelectedIndexChanged += OnProfileChanged;
            UpdateTotal();
            ResumeLayout(false);
            PerformLayout();

            Load += delegate
            {
                try { split.SplitterDistance = (int)(split.Width * 0.56); } catch { }
                if (tree.Nodes.Count > 0) tree.SelectedNode = tree.Nodes[0];
                LayoutDetails(detail);
            };
        }

        void LayoutDetails(Panel detail)
        {
            int w = Math.Max(200, detail.ClientSize.Width - 30);
            detailTitle.MaximumSize = new Size(w, 0);
            detailText.MaximumSize = new Size(w, 0);
            detailText.Top = detailTitle.Bottom + 8;
            optionPanel.Location = new Point(10, detailText.Bottom + 10);
        }

        static string NodeText(CheckInfo ci)
        {
            string s = ci.Title + "   (" + Ui.Duration(ci.EstimatedSeconds());
            if (ci.Interactive) s += ", mit Mithilfe";
            return s + ")";
        }

        static bool AnyChecked(TreeNode cat)
        {
            foreach (TreeNode n in cat.Nodes) if (n.Checked) return true;
            return false;
        }

        void BuildTree()
        {
            tree.BeginUpdate();
            tree.Nodes.Clear();
            List<CheckInfo> sorted = new List<CheckInfo>(checks);
            sorted.Sort(delegate(CheckInfo a, CheckInfo b)
            {
                int c = a.CategoryOrder.CompareTo(b.CategoryOrder);
                if (c != 0) return c;
                c = string.CompareOrdinal(a.Category, b.Category);
                if (c != 0) return c;
                return a.Order.CompareTo(b.Order);
            });
            TreeNode cat = null;
            foreach (CheckInfo ci in sorted)
            {
                if (cat == null || (string)cat.Tag != ci.Category)
                {
                    cat = new TreeNode(ci.Category.ToUpperInvariant());
                    cat.Tag = ci.Category;
                    tree.Nodes.Add(cat);
                }
                TreeNode n = new TreeNode(NodeText(ci));
                n.Tag = ci;
                n.Checked = ci.Selected;
                cat.Nodes.Add(n);
            }
            updating = true;
            foreach (TreeNode c in tree.Nodes) c.Checked = AnyChecked(c);
            updating = false;
            tree.ExpandAll();
            tree.EndUpdate();
        }

        void OnAfterCheck(object sender, TreeViewEventArgs e)
        {
            if (updating) return;
            updating = true;
            try
            {
                CheckInfo ci = e.Node.Tag as CheckInfo;
                if (ci != null)
                {
                    ci.Selected = e.Node.Checked;
                    if (e.Node.Parent != null) e.Node.Parent.Checked = AnyChecked(e.Node.Parent);
                }
                else
                {
                    foreach (TreeNode c in e.Node.Nodes)
                    {
                        c.Checked = e.Node.Checked;
                        CheckInfo cc = c.Tag as CheckInfo;
                        if (cc != null) cc.Selected = e.Node.Checked;
                    }
                }
                ProfileId = "custom";
                profileBox.SelectedIndex = profiles.Count;
                UpdateProfileDesc();
            }
            finally { updating = false; }
            UpdateTotal();
        }

        void OnProfileChanged(object sender, EventArgs e)
        {
            if (updating) return;
            int i = profileBox.SelectedIndex;
            if (i < 0 || i >= profiles.Count) { ProfileId = "custom"; UpdateProfileDesc(); return; }
            ApplyProfile(profiles[i].Id);
        }

        void SelectProfileEntry(string id)
        {
            int idx = profiles.FindIndex(delegate(ProfileInfo p) { return p.Id == id; });
            updating = true;
            profileBox.SelectedIndex = idx >= 0 ? idx : profiles.Count;
            updating = false;
            ProfileId = idx >= 0 ? id : "custom";
            UpdateProfileDesc();
        }

        void ApplyProfile(string id)
        {
            ProfileId = id;
            updating = true;
            try
            {
                foreach (TreeNode cat in tree.Nodes)
                {
                    foreach (TreeNode n in cat.Nodes)
                    {
                        CheckInfo ci = (CheckInfo)n.Tag;
                        ci.Selected = ci.InProfile(id);
                        n.Checked = ci.Selected;
                    }
                    cat.Checked = AnyChecked(cat);
                }
            }
            finally { updating = false; }
            UpdateProfileDesc();
            UpdateTotal();
        }

        void UpdateProfileDesc()
        {
            ProfileInfo p = profiles.Find(delegate(ProfileInfo x) { return x.Id == ProfileId; });
            profileDesc.Text = p != null ? p.Description : "Eigene Auswahl.";
        }

        void UpdateTotal()
        {
            int sel = 0, secs = 0, inter = 0;
            foreach (CheckInfo ci in checks)
            {
                if (!ci.Selected) continue;
                sel++;
                secs += ci.EstimatedSeconds();
                if (ci.Interactive) inter++;
            }
            totalLabel.Text = "Ausgewählt: " + sel + " von " + checks.Count + " Tests  ·  geschätzte Dauer: " + Ui.Duration(secs) +
                (inter > 0 ? "  ·  " + inter + " davon mit Mithilfe" : "");
        }

        void ShowDetails(TreeNode node)
        {
            optionPanel.SuspendLayout();
            optionPanel.Controls.Clear();
            CheckInfo ci = node == null ? null : node.Tag as CheckInfo;
            if (ci == null)
            {
                detailTitle.Text = node == null ? "" : node.Text;
                detailText.Text = "Kategorie. Ein Häkchen hier wählt alle Tests dieser Gruppe aus oder ab.\r\nKlicke auf einen einzelnen Test, um seine Beschreibung und Einstellungen zu sehen.";
            }
            else
            {
                detailTitle.Text = ci.Title;
                string info = ci.Description + "\r\n\r\nGeschätzte Dauer: " + Ui.Duration(ci.EstimatedSeconds());
                if (ci.Interactive) info += "\r\nMithilfe nötig: Ja – du wirst während des Tests um Eingaben gebeten.";
                if (ci.NeedsAcPower) info += "\r\nNetzteil: bitte angeschlossen lassen.";
                detailText.Text = info;
                foreach (CheckOption o in ci.Options)
                {
                    FlowLayoutPanel row = new FlowLayoutPanel();
                    row.AutoSize = true;
                    row.WrapContents = false;
                    row.Margin = new Padding(0, 4, 0, 4);
                    Label l = new Label();
                    l.Text = o.Label + ":";
                    l.AutoSize = true;
                    l.Margin = new Padding(3, 6, 6, 0);
                    NumericUpDown nud = new NumericUpDown();
                    nud.Minimum = o.Min;
                    nud.Maximum = o.Max;
                    nud.Increment = o.Increment;
                    nud.DecimalPlaces = o.DecimalPlaces;
                    nud.Value = Math.Max(o.Min, Math.Min(o.Max, o.Value));
                    nud.Width = 80;
                    nud.Tag = new object[] { ci, o, node };
                    nud.ValueChanged += OnOptionChanged;
                    row.Controls.Add(l);
                    row.Controls.Add(nud);
                    if (!string.IsNullOrEmpty(o.Unit))
                    {
                        Label u = new Label();
                        u.Text = o.Unit;
                        u.AutoSize = true;
                        u.Margin = new Padding(3, 6, 3, 0);
                        row.Controls.Add(u);
                    }
                    optionPanel.Controls.Add(row);
                }
            }
            optionPanel.ResumeLayout();
            if (detailText.Parent != null) LayoutDetails((Panel)detailText.Parent);
        }

        void OnOptionChanged(object sender, EventArgs e)
        {
            NumericUpDown nud = (NumericUpDown)sender;
            object[] t = (object[])nud.Tag;
            CheckInfo ci = (CheckInfo)t[0];
            CheckOption o = (CheckOption)t[1];
            TreeNode n = (TreeNode)t[2];
            o.Value = nud.Value;
            n.Text = NodeText(ci);
            UpdateTotal();
        }

        void OnStart(object sender, EventArgs e)
        {
            bool any = false;
            foreach (CheckInfo ci in checks) if (ci.Selected) { any = true; break; }
            if (!any)
            {
                MessageBox.Show(this, "Bitte mindestens einen Test auswählen.", "BuyCheck", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    // ================================================================== Fragen / Hinweise
    public class AskResult
    {
        public bool Cancelled = true;
        public int Choice = -1;
        public string ChoiceText = "";
        public bool[] Checked = new bool[0];
        public List<string> CheckedTexts = new List<string>();
        public string Comment = "";
    }

    public class AskDialog : Form
    {
        readonly RadioButton[] radios;
        readonly CheckBox[] boxes;
        readonly TextBox comment;
        readonly Button okButton;
        readonly string[] options;
        public AskResult Result = new AskResult();

        public AskDialog(string title, string question, string[] options, bool multi, bool withComment, string okText, string cancelText)
        {
            this.options = options ?? new string[0];
            Ui.Init(this, title, 660, 200);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;

            TableLayoutPanel t = new TableLayoutPanel();
            t.ColumnCount = 1;
            t.AutoSize = true;
            t.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            t.Padding = new Padding(16, 14, 16, 10);
            t.Location = new Point(0, 0);
            t.Controls.Add(Ui.Wrap(question, 620, Ui.BaseFont, Color.Empty));

            radios = new RadioButton[0];
            boxes = new CheckBox[0];
            if (this.options.Length > 0)
            {
                if (multi)
                {
                    boxes = new CheckBox[this.options.Length];
                    for (int i = 0; i < this.options.Length; i++)
                    {
                        CheckBox c = new CheckBox();
                        c.Text = this.options[i];
                        c.AutoSize = true;
                        c.MaximumSize = new Size(620, 0);
                        c.Margin = new Padding(12, 3, 3, 3);
                        boxes[i] = c;
                        t.Controls.Add(c);
                    }
                }
                else
                {
                    radios = new RadioButton[this.options.Length];
                    for (int i = 0; i < this.options.Length; i++)
                    {
                        RadioButton r = new RadioButton();
                        r.Text = this.options[i];
                        r.AutoSize = true;
                        r.MaximumSize = new Size(620, 0);
                        r.Margin = new Padding(12, 3, 3, 3);
                        r.CheckedChanged += delegate { okButton.Enabled = true; };
                        radios[i] = r;
                        t.Controls.Add(r);
                    }
                }
            }
            if (withComment)
            {
                Label cl = Ui.Wrap("Anmerkung (optional):", 620, Ui.SmallFont, Ui.Gray);
                cl.Margin = new Padding(3, 12, 3, 2);
                t.Controls.Add(cl);
                comment = new TextBox();
                comment.Width = 620;
                t.Controls.Add(comment);
            }
            FlowLayoutPanel b = new FlowLayoutPanel();
            b.FlowDirection = FlowDirection.RightToLeft;
            b.AutoSize = true;
            b.Dock = DockStyle.Fill;
            b.Margin = new Padding(0, 12, 0, 0);
            okButton = Ui.Btn(okText ?? "Weiter", OnOk);
            okButton.Font = Ui.BoldFont;
            okButton.Enabled = radios.Length == 0;
            b.Controls.Add(okButton);
            if (!string.IsNullOrEmpty(cancelText))
            {
                Button c = Ui.Btn(cancelText, delegate { Result.Cancelled = true; DialogResult = DialogResult.Cancel; Close(); });
                b.Controls.Add(c);
                CancelButton = c;
            }
            t.Controls.Add(b);
            Controls.Add(t);
            AcceptButton = okButton;
            ResumeLayout(false);
            PerformLayout();
        }

        void OnOk(object sender, EventArgs e)
        {
            Result.Cancelled = false;
            for (int i = 0; i < radios.Length; i++)
                if (radios[i].Checked) { Result.Choice = i; Result.ChoiceText = options[i]; }
            Result.Checked = new bool[boxes.Length];
            for (int i = 0; i < boxes.Length; i++)
            {
                Result.Checked[i] = boxes[i].Checked;
                if (boxes[i].Checked) Result.CheckedTexts.Add(options[i]);
            }
            if (comment != null) Result.Comment = comment.Text.Trim();
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    public static class Ask
    {
        public static AskResult Choice(string title, string question, string[] options, bool withComment)
        {
            using (AskDialog d = new AskDialog(title, question, options, false, withComment, "Weiter", null)) { d.ShowDialog(); return d.Result; }
        }

        public static AskResult Multi(string title, string question, string[] options, bool withComment)
        {
            using (AskDialog d = new AskDialog(title, question, options, true, withComment, "Weiter", null)) { d.ShowDialog(); return d.Result; }
        }

        // true = OK/Weiter, false = Abbrechen/Überspringen
        public static bool Info(string title, string message, string okText, string cancelText)
        {
            using (AskDialog d = new AskDialog(title, message, new string[0], false, false, okText, cancelText))
            {
                return d.ShowDialog() == DialogResult.OK;
            }
        }

        // Rückgabe null = abgebrochen
        public static string Input(string title, string prompt, string preset)
        {
            using (Form f = new Form())
            {
                Ui.Init(f, title, 640, 190);
                f.FormBorderStyle = FormBorderStyle.FixedDialog;
                f.MaximizeBox = false;
                Label l = Ui.Wrap(prompt, 600, Ui.BaseFont, Color.Empty);
                l.Location = new Point(16, 14);
                TextBox tb = new TextBox();
                tb.Multiline = true;
                tb.ScrollBars = ScrollBars.Vertical;
                tb.Text = preset ?? "";
                tb.SetBounds(16, 70, 600, 60);
                Button ok = Ui.Btn("OK", delegate { f.DialogResult = DialogResult.OK; f.Close(); });
                Button cancel = Ui.Btn("Abbrechen", delegate { f.DialogResult = DialogResult.Cancel; f.Close(); });
                ok.Location = new Point(440, 140);
                cancel.Location = new Point(520, 140);
                f.Controls.Add(l);
                f.Controls.Add(tb);
                f.Controls.Add(ok);
                f.Controls.Add(cancel);
                f.CancelButton = cancel;
                f.ResumeLayout(false);
                f.Load += delegate
                {
                    tb.Top = l.Bottom + 8;
                    ok.Top = cancel.Top = tb.Bottom + 10;
                    cancel.Left = f.ClientSize.Width - cancel.Width - 16;
                    ok.Left = cancel.Left - ok.Width - 8;
                    f.ClientSize = new Size(f.ClientSize.Width, ok.Bottom + 12);
                };
                return f.ShowDialog() == DialogResult.OK ? tb.Text.Trim() : null;
            }
        }
    }

    // ================================================================== Basis für interaktive Testfenster
    public class TestFormBase : Form
    {
        protected readonly Panel Content;
        protected readonly Label Instructions;
        protected readonly TextBox CommentBox;
        protected readonly Button OkBtn;
        protected readonly Button ProblemBtn;
        protected readonly Button SkipBtn;
        public InteractiveResult Result = new InteractiveResult();

        public TestFormBase(string title, string instructions, int width, int height, bool withComment)
        {
            Ui.Init(this, title, width, height);
            MinimumSize = new Size(Math.Min(width, 700), Math.Min(height, 450));

            Instructions = new Label();
            Instructions.Text = instructions ?? "";
            Instructions.Dock = DockStyle.Top;
            Instructions.AutoSize = false;
            Instructions.Padding = new Padding(14, 10, 14, 6);
            Instructions.BackColor = Ui.PanelGray;

            // Fußbereich als Tabelle: (Anmerkung) + Buttons untereinander – keine Überlappung möglich
            TableLayoutPanel bottom = new TableLayoutPanel();
            bottom.Dock = DockStyle.Bottom;
            bottom.AutoSize = true;
            bottom.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bottom.BackColor = Ui.PanelGray;
            bottom.Padding = new Padding(10, 6, 10, 6);
            bottom.ColumnCount = 1;
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
            if (withComment)
            {
                Label cl = new Label();
                cl.Text = "Anmerkung (optional):";
                cl.AutoSize = true;
                cl.ForeColor = Ui.Gray;
                cl.Margin = new Padding(3, 3, 3, 0);
                CommentBox = new TextBox();
                CommentBox.Dock = DockStyle.Fill;
                CommentBox.Margin = new Padding(3, 2, 3, 2);
                bottom.Controls.Add(cl);
                bottom.Controls.Add(CommentBox);
            }
            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.AutoSize = true;
            buttons.WrapContents = false;
            buttons.Dock = DockStyle.Fill;
            buttons.Margin = new Padding(0);
            SkipBtn = Ui.Btn("Überspringen", delegate { if (OnSkipClicked()) Finish("Skip"); });
            ProblemBtn = Ui.Btn("✖  Problem gefunden", delegate { if (OnProblemClicked()) Finish("Problem"); });
            OkBtn = Ui.Btn("✔  Funktioniert", delegate { if (OnOkClicked()) Finish("OK"); });
            OkBtn.Font = Ui.BoldFont;
            buttons.Controls.Add(SkipBtn);
            buttons.Controls.Add(ProblemBtn);
            buttons.Controls.Add(OkBtn);
            bottom.Controls.Add(buttons);

            Content = new Panel();
            Content.Dock = DockStyle.Fill;
            Content.Padding = new Padding(10);

            Controls.Add(Content);
            Controls.Add(bottom);
            Controls.Add(Instructions);
            Resize += delegate { Ui.FitHeight(Instructions, ClientSize.Width); };
            Load += delegate { Ui.FitHeight(Instructions, ClientSize.Width); };
        }

        protected void FinishLayout()
        {
            ResumeLayout(false);
            PerformLayout();
        }

        protected virtual bool OnOkClicked() { return true; }
        protected virtual bool OnProblemClicked() { return true; }
        protected virtual bool OnSkipClicked() { return true; }
        protected virtual void CollectDetails() { }

        void Finish(string verdict)
        {
            Result.Verdict = verdict;
            if (CommentBox != null && CommentBox.Text.Trim().Length > 0) Result.Comment = CommentBox.Text.Trim();
            CollectDetails();
            DialogResult = DialogResult.OK;
            Close();
        }
    }

    // ================================================================== Pixelfehler-/Ausleuchtungstest (Vollbild)
    public class PixelTestForm : Form
    {
        static readonly Color[] Colors = new Color[] {
            Color.Black, Color.White, Color.FromArgb(255, 0, 0), Color.FromArgb(0, 255, 0), Color.FromArgb(0, 0, 255),
            Color.FromArgb(128, 128, 128), Color.FromArgb(18, 18, 18), Color.Black };
        static readonly string[] Names = new string[] {
            "Schwarz: Suche helle oder farbige Punkte und helle Ränder.",
            "Weiß: Suche dunkle Punkte, Flecken und Verfärbungen.",
            "Rot: Suche Punkte, die nicht rot leuchten.",
            "Grün: Suche Punkte, die nicht grün leuchten.",
            "Blau: Suche Punkte, die nicht blau leuchten.",
            "Grau: Suche Wolken, Flecken und ungleichmäßige Helligkeit.",
            "Fast schwarz: Lichthöfe an den Rändern (Backlight Bleeding) sind hier am besten sichtbar.",
            "Farbverläufe: Sollten gleichmäßig sein, ohne harte Stufen oder Streifen." };
        int index;
        readonly Label hint;
        readonly Timer hintTimer;
        public int FramesSeen;

        public PixelTestForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = Screen.PrimaryScreen.Bounds;
            TopMost = true;
            KeyPreview = true;
            DoubleBuffered = true;
            ShowInTaskbar = false;
            BackColor = Color.Black;
            hint = new Label();
            hint.AutoSize = true;
            hint.Font = new Font("Segoe UI", 13F);
            hint.BackColor = Color.FromArgb(255, 255, 225);
            hint.ForeColor = Color.Black;
            hint.Padding = new Padding(10);
            hint.Location = new Point(30, 30);
            Controls.Add(hint);
            hintTimer = new Timer();
            hintTimer.Interval = 3500;
            hintTimer.Tick += delegate { hintTimer.Stop(); hint.Visible = false; };
            KeyDown += OnKeyDownHandler;
            MouseUp += OnMouseUpHandler;
            hint.MouseUp += OnMouseUpHandler;
            Shown += delegate { Cursor.Hide(); ShowFrame(0); Activate(); };
            FormClosed += delegate { Cursor.Show(); hintTimer.Dispose(); };
        }

        void ShowFrame(int i)
        {
            if (i >= Colors.Length) { Close(); return; }
            if (i < 0) i = 0;
            index = i;
            FramesSeen = Math.Max(FramesSeen, i + 1);
            BackColor = Colors[i];
            hint.Text = (i + 1) + "/" + Colors.Length + "  –  " + Names[i] +
                "\nLeertaste/Klick = weiter · Pfeil links/Rechtsklick = zurück · Esc = beenden";
            hint.Visible = true;
            hintTimer.Stop();
            hintTimer.Start();
            Invalidate();
        }

        void OnKeyDownHandler(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape) Close();
            else if (e.KeyCode == Keys.Left || e.KeyCode == Keys.Back) ShowFrame(index - 1);
            else if (e.KeyCode == Keys.H) { hint.Visible = !hint.Visible; }
            else ShowFrame(index + 1);
            e.Handled = true;
        }

        void OnMouseUpHandler(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right) ShowFrame(index - 1);
            else ShowFrame(index + 1);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (index != Colors.Length - 1) return;
            Rectangle r = ClientRectangle;
            int h = r.Height / 4;
            Color[] ends = new Color[] { Color.White, Color.FromArgb(255, 0, 0), Color.FromArgb(0, 255, 0), Color.FromArgb(0, 0, 255) };
            for (int i = 0; i < 4; i++)
            {
                Rectangle band = new Rectangle(r.Left, r.Top + i * h, r.Width, (i == 3) ? r.Height - 3 * h : h);
                using (LinearGradientBrush b = new LinearGradientBrush(band, Color.Black, ends[i], LinearGradientMode.Horizontal))
                {
                    e.Graphics.FillRectangle(b, band);
                }
            }
        }
    }

    // ================================================================== Tastaturtest
    public class KeyboardTestForm : TestFormBase
    {
        class KeyDef
        {
            public string Label;
            public int Code;
            public float X, Y, W, H;
            public bool Optional;
            public bool Pressed;
        }

        class KeyCanvas : Control
        {
            readonly KeyboardTestForm owner;
            public KeyCanvas(KeyboardTestForm o)
            {
                owner = o;
                SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
                BackColor = Color.White;
            }
            protected override void OnPaint(PaintEventArgs e) { owner.PaintKeys(e.Graphics, ClientRectangle); }
        }

        [DllImport("user32.dll")]
        static extern int GetMessageTime();

        readonly List<KeyDef> keys = new List<KeyDef>();
        readonly Dictionary<int, KeyDef> byCode = new Dictionary<int, KeyDef>();
        readonly List<string> extras = new List<string>();
        readonly KeyCanvas canvas;
        readonly Label status;
        KeyDef pendingCtrl;
        int pendingCtrlTime;

        public KeyboardTestForm()
            : base("Tastaturtest",
                "Drücke nacheinander JEDE Taste einmal – gedrückte Tasten werden grün. F-Tasten ggf. zusammen mit Fn drücken. " +
                "Gestrichelte Tasten sind optional (nicht jeder Laptop hat sie). Die Windows-Taste bitte zuletzt drücken, " +
                "sie öffnet das Startmenü (danach wieder in dieses Fenster klicken). Die Fn-Taste allein kann kein Programm erkennen.",
                1180, 640, false)
        {
            KeyPreview = true;
            BuildLayout();
            canvas = new KeyCanvas(this);
            canvas.Dock = DockStyle.Fill;
            status = new Label();
            status.Dock = DockStyle.Bottom;
            status.Height = 62;
            status.Padding = new Padding(6);
            Content.Controls.Add(canvas);
            Content.Controls.Add(status);
            OkBtn.Text = "✔  Alle Tasten funktionieren";
            ProblemBtn.Text = "✖  Defekte Tasten melden";
            UpdateStatus();
            FinishLayout();
            Shown += delegate { Activate(); canvas.Focus(); };
        }

        void K(string label, int code, float x, float y, float w, bool optional) { K(label, code, x, y, w, 1f, optional); }

        void K(string label, int code, float x, float y, float w, float h, bool optional)
        {
            KeyDef k = new KeyDef();
            k.Label = label; k.Code = code; k.X = x; k.Y = y; k.W = w; k.H = h; k.Optional = optional;
            keys.Add(k);
            byCode[code] = k;
        }

        void BuildLayout()
        {
            // Reihe 0: Esc, F-Tasten
            K("Esc", 0x01, 0, 0, 1, false);
            string[] f = { "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12" };
            int[] fc = { 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x57, 0x58 };
            for (int i = 0; i < 12; i++) K(f[i], fc[i], 1.25f + i + (i / 4) * 0.25f, 0, 1, false);
            // Reihe 1
            K("^", 0x29, 0, 1.25f, 1, false);
            string[] r1 = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "ß", "´" };
            for (int i = 0; i < r1.Length; i++) K(r1[i], 0x02 + i, 1 + i, 1.25f, 1, false);
            K("⌫", 0x0E, 13, 1.25f, 2, false);
            // Reihe 2
            K("Tab", 0x0F, 0, 2.25f, 1.5f, false);
            string[] r2 = { "Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "Ü", "+" };
            for (int i = 0; i < r2.Length; i++) K(r2[i], 0x10 + i, 1.5f + i, 2.25f, 1, false);
            K("Enter", 0x1C, 13.75f, 2.25f, 1.25f, 2f, false);
            // Reihe 3
            K("Caps", 0x3A, 0, 3.25f, 1.75f, false);
            string[] r3 = { "A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö", "Ä" };
            for (int i = 0; i < r3.Length; i++) K(r3[i], 0x1E + i, 1.75f + i, 3.25f, 1, false);
            K("#", 0x2B, 12.75f, 3.25f, 1, false);
            // Reihe 4
            K("⇧", 0x2A, 0, 4.25f, 1.25f, false);
            K("<", 0x56, 1.25f, 4.25f, 1, false);
            string[] r4 = { "Y", "X", "C", "V", "B", "N", "M", ",", ".", "-" };
            for (int i = 0; i < r4.Length; i++) K(r4[i], 0x2C + i, 2.25f + i, 4.25f, 1, false);
            K("⇧ rechts", 0x36, 12.25f, 4.25f, 2.75f, false);
            // Reihe 5
            K("Strg", 0x1D, 0, 5.25f, 1.5f, false);
            K("Win", 0x15B, 1.5f, 5.25f, 1.25f, false);
            K("Alt", 0x38, 2.75f, 5.25f, 1.25f, false);
            K("Leertaste", 0x39, 4, 5.25f, 5.5f, false);
            K("AltGr", 0x138, 9.5f, 5.25f, 1.25f, false);
            K("Menü", 0x15D, 10.75f, 5.25f, 1, true);
            K("Strg r.", 0x11D, 11.75f, 5.25f, 1.25f, true);
            // Pfeiltasten
            K("↑", 0x148, 16.5f, 4.25f, 1, false);
            K("←", 0x14B, 15.5f, 5.25f, 1, false);
            K("↓", 0x150, 16.5f, 5.25f, 1, false);
            K("→", 0x14D, 17.5f, 5.25f, 1, false);
            // Navigationsblock
            K("Druck", 0x102C, 15.5f, 0, 1, true);
            K("Rollen", 0x46, 16.5f, 0, 1, true);
            K("Pause", 0x1013, 17.5f, 0, 1, true);
            K("Einfg", 0x152, 15.5f, 1.25f, 1, true);
            K("Pos1", 0x147, 16.5f, 1.25f, 1, true);
            K("Bild↑", 0x149, 17.5f, 1.25f, 1, true);
            K("Entf", 0x153, 15.5f, 2.25f, 1, false);
            K("Ende", 0x14F, 16.5f, 2.25f, 1, true);
            K("Bild↓", 0x151, 17.5f, 2.25f, 1, true);
            // Ziffernblock (optional)
            K("Num", 0x1090, 19, 1.25f, 1, true);
            K("/", 0x135, 20, 1.25f, 1, true);
            K("*", 0x37, 21, 1.25f, 1, true);
            K("-", 0x4A, 22, 1.25f, 1, true);
            K("7", 0x47, 19, 2.25f, 1, true);
            K("8", 0x48, 20, 2.25f, 1, true);
            K("9", 0x49, 21, 2.25f, 1, true);
            K("+", 0x4E, 22, 2.25f, 1, 2f, true);
            K("4", 0x4B, 19, 3.25f, 1, true);
            K("5", 0x4C, 20, 3.25f, 1, true);
            K("6", 0x4D, 21, 3.25f, 1, true);
            K("1", 0x4F, 19, 4.25f, 1, true);
            K("2", 0x50, 20, 4.25f, 1, true);
            K("3", 0x51, 21, 4.25f, 1, true);
            K("Enter", 0x11C, 22, 4.25f, 1, 2f, true);
            K("0", 0x52, 19, 5.25f, 2, true);
            K(",", 0x53, 21, 5.25f, 1, true);
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (msg.Msg == 0x0100 || msg.Msg == 0x0104) // WM_KEYDOWN / WM_SYSKEYDOWN
            {
                HandleKey((int)msg.WParam.ToInt64(), msg.LParam.ToInt64());
                return true; // Taste wird hier "verschluckt" – keine Wirkung auf Windows
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        protected override void OnKeyUp(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.PrintScreen) Mark(0x102C, "Druck");
            e.Handled = true;
            base.OnKeyUp(e);
        }

        protected override void WndProc(ref Message m)
        {
            // Alt/F10 würden sonst das Systemmenü aktivieren
            if (m.Msg == 0x0112 && (m.WParam.ToInt64() & 0xFFF0) == 0xF100) return;
            base.WndProc(ref m);
        }

        void HandleKey(int vk, long lParam)
        {
            int scan = (int)((lParam >> 16) & 0xFF);
            bool ext = ((lParam >> 24) & 1) != 0;
            int code;
            if (vk == 0x13) code = 0x1013;        // Pause
            else if (vk == 0x90) code = 0x1090;   // NumLock
            else if (vk == 0x2C) code = 0x102C;   // Druck
            else code = scan | (ext ? 0x100 : 0);
            int t = GetMessageTime();
            KeyDef kd;
            bool known = byCode.TryGetValue(code, out kd);
            bool wasPressed = known && kd.Pressed;
            // AltGr erzeugt unter Windows zusätzlich ein künstliches "Strg links" – das nicht mitzählen
            if (code == 0x138 && pendingCtrl != null && t == pendingCtrlTime) pendingCtrl.Pressed = false;
            pendingCtrl = null;
            Mark(code, ((Keys)vk).ToString());
            if (code == 0x1D && known && !wasPressed) { pendingCtrl = kd; pendingCtrlTime = t; }
        }

        void Mark(int code, string name)
        {
            KeyDef k;
            if (byCode.TryGetValue(code, out k)) k.Pressed = true;
            else
            {
                string s = name + " (0x" + code.ToString("X") + ")";
                if (!extras.Contains(s)) extras.Add(s);
            }
            UpdateStatus();
            canvas.Invalidate();
        }

        List<string> Missing()
        {
            List<string> m = new List<string>();
            foreach (KeyDef k in keys) if (!k.Optional && !k.Pressed) m.Add(k.Label);
            return m;
        }

        void UpdateStatus()
        {
            int req = 0, done = 0, opt = 0;
            foreach (KeyDef k in keys)
            {
                if (k.Optional) { if (k.Pressed) opt++; continue; }
                req++;
                if (k.Pressed) done++;
            }
            List<string> miss = Missing();
            string missText = miss.Count == 0 ? "keine" :
                string.Join(", ", miss.GetRange(0, Math.Min(30, miss.Count)).ToArray()) + (miss.Count > 30 ? " …" : "");
            status.Text = "Pflichttasten: " + done + " von " + req + " erkannt · optionale Tasten erkannt: " + opt +
                "\nNoch nicht gedrückt: " + missText +
                (extras.Count > 0 ? "\nWeitere erkannte Tasten: " + string.Join(", ", extras.ToArray()) : "");
            status.ForeColor = miss.Count == 0 ? Ui.Green : Color.Black;
        }

        void PaintKeys(Graphics g, Rectangle r)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float maxX = 0, maxY = 0;
            foreach (KeyDef k in keys) { maxX = Math.Max(maxX, k.X + k.W); maxY = Math.Max(maxY, k.Y + k.H); }
            float u = Math.Min((r.Width - 20) / maxX, (r.Height - 10) / maxY);
            if (u < 8) return;
            float ox = r.Left + (r.Width - maxX * u) / 2;
            float oy = r.Top + 5;
            using (Font font = new Font("Segoe UI", Math.Max(7f, u * 0.27f), FontStyle.Regular, GraphicsUnit.Pixel))
            using (Pen grayPen = new Pen(Color.FromArgb(175, 184, 193)))
            using (Pen greenPen = new Pen(Ui.Green, 2f))
            using (Pen dashed = new Pen(Color.FromArgb(175, 184, 193)))
            using (SolidBrush pressedBrush = new SolidBrush(Ui.PressedGreen))
            using (SolidBrush normalBrush = new SolidBrush(Ui.KeyGray))
            using (SolidBrush optionalBrush = new SolidBrush(Color.White))
            using (StringFormat sf = new StringFormat())
            {
                dashed.DashStyle = DashStyle.Dash;
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                foreach (KeyDef k in keys)
                {
                    RectangleF kr = new RectangleF(ox + k.X * u + 2, oy + k.Y * u + 2, k.W * u - 4, k.H * u - 4);
                    g.FillRectangle(k.Pressed ? pressedBrush : (k.Optional ? optionalBrush : normalBrush), kr);
                    g.DrawRectangle(k.Pressed ? greenPen : (k.Optional ? dashed : grayPen), kr.X, kr.Y, kr.Width, kr.Height);
                    g.DrawString(k.Label, font, k.Pressed ? Brushes.White : Brushes.Black, kr, sf);
                }
            }
        }

        protected override bool OnOkClicked()
        {
            List<string> miss = Missing();
            if (miss.Count == 0) return true;
            DialogResult r = MessageBox.Show(this,
                "Diese Pflichttasten wurden noch nicht erkannt:\n\n" + string.Join(", ", miss.ToArray()) +
                "\n\nTrotzdem als „funktioniert“ werten (z. B. weil der Laptop diese Tasten nicht hat)?",
                "Tastaturtest", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return false;
            Result.Details.Add("Nicht erkannt, aber als OK bestätigt: " + string.Join(", ", miss.ToArray()));
            return true;
        }

        protected override bool OnProblemClicked()
        {
            string s = Ask.Input("Defekte Tasten", "Welche Tasten funktionieren nicht oder klemmen? (vorausgefüllt mit den nicht erkannten Pflichttasten)",
                string.Join(", ", Missing().ToArray()));
            if (s == null) return false;
            Result.Problems.Add(s.Length > 0 ? s : "Defekte Tasten (ohne Angabe)");
            return true;
        }

        protected override void CollectDetails()
        {
            int pressed = 0;
            foreach (KeyDef k in keys) if (k.Pressed) pressed++;
            Result.Details.Add("Erkannte Tasten im Layout: " + pressed + " von " + keys.Count);
            if (extras.Count > 0) Result.Details.Add("Weitere erkannte Tasten: " + string.Join(", ", extras.ToArray()));
        }
    }

    // ================================================================== Touchpad-/Maustest
    public class TouchpadTestForm : TestFormBase
    {
        class Target
        {
            public string Name;
            public string Kind;      // hover, left, right, double, wheelUp, wheelDown, hwheel
            public float FX, FY;     // Position relativ (0..1)
            public int Needed = 1;
            public int Count;
            public bool Optional;
            public RectangleF Rect;
            public bool Done { get { return Count >= Needed; } }
        }

        class PadCanvas : Control
        {
            readonly TouchpadTestForm owner;
            public PadCanvas(TouchpadTestForm o)
            {
                owner = o;
                SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                    ControlStyles.ResizeRedraw | ControlStyles.Selectable | ControlStyles.StandardDoubleClick, true);
                BackColor = Color.White;
                TabStop = true;
            }
            protected override void OnPaint(PaintEventArgs e) { owner.PaintPad(e.Graphics, ClientRectangle); }
            protected override void OnMouseEnter(EventArgs e) { Focus(); base.OnMouseEnter(e); }
            protected override void WndProc(ref Message m)
            {
                if (m.Msg == 0x020E) owner.OnHWheel(); // WM_MOUSEHWHEEL
                base.WndProc(ref m);
            }
        }

        readonly List<Target> targets = new List<Target>();
        readonly List<Point> path = new List<Point>();
        readonly PadCanvas canvas;
        readonly Label status;

        public TouchpadTestForm()
            : base("Touchpad-Test",
                "Teste das Touchpad (nicht eine angeschlossene Maus): Fahre in alle vier Ecken, klicke die Felder mit der linken bzw. rechten Taste " +
                "(bzw. Touchpad-Tasten), mache einen Doppelklick und scrolle mit zwei Fingern nach oben und unten. Die Spur zeigt, ob der Zeiger springt.",
                1000, 680, true)
        {
            AddTarget("Ecke oben links", "hover", 0.04f, 0.06f, 1, false);
            AddTarget("Ecke oben rechts", "hover", 0.96f, 0.06f, 1, false);
            AddTarget("Ecke unten links", "hover", 0.04f, 0.94f, 1, false);
            AddTarget("Ecke unten rechts", "hover", 0.96f, 0.94f, 1, false);
            AddTarget("Linksklick", "left", 0.25f, 0.35f, 1, false);
            AddTarget("Rechtsklick", "right", 0.5f, 0.35f, 1, false);
            AddTarget("Doppelklick", "double", 0.75f, 0.35f, 1, false);
            AddTarget("Scrollen ↑ (3×)", "wheelUp", 0.3f, 0.68f, 3, false);
            AddTarget("Scrollen ↓ (3×)", "wheelDown", 0.55f, 0.68f, 3, false);
            AddTarget("Seitlich scrollen (optional)", "hwheel", 0.8f, 0.68f, 2, true);
            canvas = new PadCanvas(this);
            canvas.Dock = DockStyle.Fill;
            canvas.MouseMove += OnMove;
            canvas.MouseDown += OnDown;
            canvas.MouseDoubleClick += OnDouble;
            canvas.MouseWheel += OnWheel;
            status = new Label();
            status.Dock = DockStyle.Bottom;
            status.Height = 30;
            Content.Controls.Add(canvas);
            Content.Controls.Add(status);
            UpdateStatus();
            FinishLayout();
        }

        void AddTarget(string name, string kind, float fx, float fy, int needed, bool optional)
        {
            Target t = new Target();
            t.Name = name; t.Kind = kind; t.FX = fx; t.FY = fy; t.Needed = needed; t.Optional = optional;
            targets.Add(t);
        }

        Target Hit(Point p, string kind)
        {
            foreach (Target t in targets) if (t.Kind == kind && t.Rect.Contains(p)) return t;
            return null;
        }

        void OnMove(object sender, MouseEventArgs e)
        {
            path.Add(e.Location);
            if (path.Count > 6000) path.RemoveRange(0, 1500);
            Target t = Hit(e.Location, "hover");
            if (t != null && !t.Done) { t.Count = t.Needed; UpdateStatus(); }
            canvas.Invalidate();
        }

        void OnDown(object sender, MouseEventArgs e)
        {
            canvas.Focus();
            Target t = null;
            if (e.Button == MouseButtons.Left) t = Hit(e.Location, "left");
            else if (e.Button == MouseButtons.Right) t = Hit(e.Location, "right");
            if (t != null) { t.Count = t.Needed; UpdateStatus(); canvas.Invalidate(); }
        }

        void OnDouble(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            Target t = Hit(e.Location, "double");
            if (t != null) { t.Count = t.Needed; UpdateStatus(); canvas.Invalidate(); }
        }

        void OnWheel(object sender, MouseEventArgs e)
        {
            string kind = e.Delta > 0 ? "wheelUp" : "wheelDown";
            foreach (Target t in targets) if (t.Kind == kind && t.Count < t.Needed) t.Count++;
            UpdateStatus();
            canvas.Invalidate();
        }

        internal void OnHWheel()
        {
            foreach (Target t in targets) if (t.Kind == "hwheel" && t.Count < t.Needed) t.Count++;
            UpdateStatus();
            canvas.Invalidate();
        }

        void UpdateStatus()
        {
            int req = 0, done = 0;
            foreach (Target t in targets) { if (t.Optional) continue; req++; if (t.Done) done++; }
            status.Text = "Erledigt: " + done + " von " + req + (done == req ? " – alles erkannt ✔" : "");
            status.ForeColor = done == req ? Ui.Green : Color.Black;
        }

        void PaintPad(Graphics g, Rectangle r)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (path.Count > 1)
            {
                using (Pen p = new Pen(Color.FromArgb(120, 9, 105, 218), 2f))
                {
                    for (int i = 1; i < path.Count; i++)
                    {
                        // große Sprünge (z. B. neues Ansetzen) nicht verbinden
                        int dx = path[i].X - path[i - 1].X, dy = path[i].Y - path[i - 1].Y;
                        if (dx * dx + dy * dy < 160 * 160) g.DrawLine(p, path[i - 1], path[i]);
                    }
                }
            }
            using (Font f = new Font("Segoe UI", 10F))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                foreach (Target t in targets)
                {
                    float w = t.Kind == "hover" ? 70 : 190, h = t.Kind == "hover" ? 70 : 70;
                    float cx = r.Left + t.FX * r.Width, cy = r.Top + t.FY * r.Height;
                    float x = Math.Max(r.Left, Math.Min(r.Right - w, cx - w / 2));
                    float y = Math.Max(r.Top, Math.Min(r.Bottom - h, cy - h / 2));
                    t.Rect = new RectangleF(x, y, w, h);
                    Color fill = t.Done ? Ui.LightGreen : (t.Optional ? Color.White : Color.FromArgb(255, 248, 197));
                    using (SolidBrush b = new SolidBrush(fill)) g.FillRectangle(b, t.Rect);
                    using (Pen p = new Pen(t.Done ? Ui.Green : Color.FromArgb(175, 184, 193), t.Done ? 2f : 1f)) g.DrawRectangle(p, x, y, w, h);
                    string label = t.Kind == "hover" ? (t.Done ? "✔" : "Ecke") : t.Name + (t.Needed > 1 ? "\n" + t.Count + "/" + t.Needed : "") + (t.Done ? "  ✔" : "");
                    g.DrawString(label, f, Brushes.Black, t.Rect, sf);
                }
            }
        }

        protected override bool OnOkClicked()
        {
            List<string> open = new List<string>();
            foreach (Target t in targets) if (!t.Optional && !t.Done) open.Add(t.Name);
            if (open.Count == 0) return true;
            DialogResult r = MessageBox.Show(this, "Noch nicht erledigt: " + string.Join(", ", open.ToArray()) +
                "\n\nTrotzdem als „funktioniert“ werten?", "Touchpad-Test", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (r != DialogResult.Yes) return false;
            Result.Details.Add("Nicht erledigt, aber als OK bestätigt: " + string.Join(", ", open.ToArray()));
            return true;
        }

        protected override bool OnProblemClicked()
        {
            foreach (Target t in targets) if (!t.Optional && !t.Done) Result.Problems.Add("Nicht erkannt: " + t.Name);
            if (Result.Problems.Count == 0) Result.Problems.Add("Problem laut Prüfer (siehe Anmerkung)");
            return true;
        }

        protected override void CollectDetails()
        {
            List<string> ok = new List<string>();
            foreach (Target t in targets) if (t.Done) ok.Add(t.Name);
            Result.Details.Add("Erkannt: " + string.Join(", ", ok.ToArray()));
        }
    }

    // ================================================================== USB-Anschlüsse
    public class UsbTestForm : TestFormBase
    {
        [DllImport("user32.dll", SetLastError = true)]
        static extern IntPtr RegisterDeviceNotification(IntPtr hRecipient, IntPtr notificationFilter, int flags);
        [DllImport("user32.dll", SetLastError = true)]
        static extern bool UnregisterDeviceNotification(IntPtr handle);

        static readonly Guid UsbDeviceInterface = new Guid("A5DCBF10-6530-11D2-901F-00C04FB951ED");
        readonly ListView list;
        readonly Label summary;
        readonly List<string> ports = new List<string>();
        readonly List<string> events = new List<string>();
        IntPtr notifyHandle = IntPtr.Zero;
        int arrivals;

        public UsbTestForm()
            : base("USB-Anschlüsse",
                "Stecke ein USB-Gerät (z. B. einen zweiten USB-Stick, eine Maus oder ein Handy-Kabel) nacheinander in JEDEN USB-Anschluss " +
                "(auch USB-C). Jedes erkannte Einstecken erscheint unten mit der Anschluss-Position. " +
                "Wichtig: Den USB-Stick, von dem dieses Programm läuft, NICHT abziehen.",
                900, 560, true)
        {
            list = new ListView();
            list.View = View.Details;
            list.FullRowSelect = true;
            list.Dock = DockStyle.Fill;
            list.Columns.Add("Zeit", 80);
            list.Columns.Add("Ereignis", 110);
            list.Columns.Add("Gerät", 300);
            list.Columns.Add("Anschluss-Position", 200);
            list.Columns.Add("Kennung", 160);
            summary = new Label();
            summary.Dock = DockStyle.Bottom;
            summary.Height = 30;
            summary.Font = Ui.BoldFont;
            Content.Controls.Add(list);
            Content.Controls.Add(summary);
            UpdateSummary();
            FinishLayout();
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            IntPtr buf = Marshal.AllocHGlobal(32);
            try
            {
                for (int i = 0; i < 32; i += 4) Marshal.WriteInt32(buf, i, 0);
                Marshal.WriteInt32(buf, 0, 32);      // dbcc_size
                Marshal.WriteInt32(buf, 4, 5);       // DBT_DEVTYP_DEVICEINTERFACE
                byte[] g = UsbDeviceInterface.ToByteArray();
                Marshal.Copy(g, 0, new IntPtr(buf.ToInt64() + 12), 16);
                notifyHandle = RegisterDeviceNotification(Handle, buf, 0); // DEVICE_NOTIFY_WINDOW_HANDLE
            }
            catch (Exception ex)
            {
                events.Add("Hinweis: Geräteerkennung konnte nicht aktiviert werden (" + ex.Message + ")");
            }
            finally { Marshal.FreeHGlobal(buf); }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            if (notifyHandle != IntPtr.Zero) { UnregisterDeviceNotification(notifyHandle); notifyHandle = IntPtr.Zero; }
            base.OnFormClosed(e);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0219 && m.LParam != IntPtr.Zero) // WM_DEVICECHANGE
            {
                long ev = m.WParam.ToInt64();
                if (ev == 0x8000 || ev == 0x8004) // DBT_DEVICEARRIVAL / DBT_DEVICEREMOVECOMPLETE
                {
                    try
                    {
                        int type = Marshal.ReadInt32(m.LParam, 4);
                        if (type == 5)
                        {
                            string name = Marshal.PtrToStringUni(new IntPtr(m.LParam.ToInt64() + 28));
                            OnDevice(ev == 0x8000, name ?? "");
                        }
                    }
                    catch { }
                }
            }
            base.WndProc(ref m);
        }

        static string CleanDesc(string s)
        {
            if (string.IsNullOrEmpty(s)) return null;
            int i = s.LastIndexOf(';');
            return i >= 0 ? s.Substring(i + 1) : s;
        }

        void OnDevice(bool arrived, string name)
        {
            // Beispiel: \\?\USB#VID_0781&PID_5567#4C530001231114117384#{a5dcbf10-6530-11d2-901f-00c04fb951ed}
            string[] parts = name.Split('#');
            string vidpid = parts.Length > 1 ? parts[1] : name;
            string inst = parts.Length > 2 ? parts[2] : "";
            string desc = "", loc = "";
            try
            {
                using (RegistryKey k = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\USB\" + vidpid + "\\" + inst))
                {
                    if (k != null)
                    {
                        desc = CleanDesc(k.GetValue("FriendlyName") as string) ?? CleanDesc(k.GetValue("DeviceDesc") as string) ?? "";
                        loc = (k.GetValue("LocationInformation") as string) ?? "";
                    }
                }
            }
            catch { }
            ListViewItem it = new ListViewItem(DateTime.Now.ToString("HH:mm:ss"));
            it.SubItems.Add(arrived ? "eingesteckt" : "abgezogen");
            it.SubItems.Add(desc.Length > 0 ? desc : "USB-Gerät");
            it.SubItems.Add(loc);
            it.SubItems.Add(vidpid);
            if (arrived) it.ForeColor = Ui.Green;
            list.Items.Insert(0, it);
            events.Add(DateTime.Now.ToString("HH:mm:ss") + " " + (arrived ? "eingesteckt" : "abgezogen") + ": " +
                (desc.Length > 0 ? desc : vidpid) + (loc.Length > 0 ? " @ " + loc : ""));
            if (arrived)
            {
                arrivals++;
                string key = loc.Length > 0 ? loc : vidpid + "#" + inst;
                if (!ports.Contains(key)) ports.Add(key);
            }
            UpdateSummary();
        }

        void UpdateSummary()
        {
            summary.Text = "Erkannte Einsteckvorgänge: " + arrivals + " · verschiedene Anschluss-Positionen: " + ports.Count;
            summary.ForeColor = arrivals > 0 ? Ui.Green : Color.Black;
        }

        protected override void CollectDetails()
        {
            Result.Details.Add("Einsteckvorgänge: " + arrivals + ", verschiedene Positionen: " + ports.Count);
            foreach (string e in events) Result.Details.Add(e);
        }

        protected override bool OnProblemClicked()
        {
            string s = Ask.Input("USB-Problem", "Welcher Anschluss funktioniert nicht bzw. was ist aufgefallen (z. B. „USB-C links reagiert nicht“, „Stecker wackelt“)?", "");
            if (s == null) return false;
            Result.Problems.Add(s.Length > 0 ? s : "USB-Problem (ohne Angabe)");
            return true;
        }
    }

    // ================================================================== Audio-Hilfen
    public static class AudioUtil
    {
        [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
        static extern int mciSendStringW(string command, StringBuilder returnString, int returnLength, IntPtr callback);

        [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
        static extern bool mciGetErrorStringW(int error, StringBuilder text, int length);

        // Stereo-WAV (16 Bit) erzeugen: Ton bzw. Gleitton von f0 nach f1
        public static byte[] MakeWav(int sampleRate, double seconds, double f0, double f1, bool left, bool right, double amplitude)
        {
            int n = (int)(sampleRate * seconds);
            int dataBytes = n * 4;
            using (MemoryStream ms = new MemoryStream(44 + dataBytes))
            using (BinaryWriter w = new BinaryWriter(ms))
            {
                w.Write(Encoding.ASCII.GetBytes("RIFF"));
                w.Write(36 + dataBytes);
                w.Write(Encoding.ASCII.GetBytes("WAVE"));
                w.Write(Encoding.ASCII.GetBytes("fmt "));
                w.Write(16);
                w.Write((short)1);
                w.Write((short)2);
                w.Write(sampleRate);
                w.Write(sampleRate * 4);
                w.Write((short)4);
                w.Write((short)16);
                w.Write(Encoding.ASCII.GetBytes("data"));
                w.Write(dataBytes);
                double phase = 0;
                int fade = Math.Max(1, Math.Min(n / 4, sampleRate / 40));
                for (int i = 0; i < n; i++)
                {
                    double t = (double)i / n;
                    double f = (Math.Abs(f0 - f1) < 0.001) ? f0 : f0 * Math.Pow(f1 / f0, t);
                    phase += 2 * Math.PI * f / sampleRate;
                    double env = 1.0;
                    if (i < fade) env = (double)i / fade;
                    else if (i > n - fade) env = (double)(n - i) / fade;
                    short s = (short)(Math.Sin(phase) * amplitude * env * 32767);
                    w.Write(left ? s : (short)0);
                    w.Write(right ? s : (short)0);
                }
                w.Flush();
                return ms.ToArray();
            }
        }

        public static void Play(byte[] wav)
        {
            using (MemoryStream ms = new MemoryStream(wav))
            using (SoundPlayer p = new SoundPlayer(ms))
            {
                p.PlaySync();
            }
        }

        public static string Mci(string command)
        {
            StringBuilder sb = new StringBuilder(256);
            int r = mciSendStringW(command, sb, sb.Capacity, IntPtr.Zero);
            if (r != 0)
            {
                StringBuilder err = new StringBuilder(256);
                mciGetErrorStringW(r, err, err.Capacity);
                throw new InvalidOperationException("Audio-Fehler (" + r + "): " + err.ToString());
            }
            return sb.ToString();
        }

        // [Spitzenpegel dBFS, Mittelwert (RMS) dBFS, Sekunden]
        public static double[] AnalyzeWav(string path)
        {
            byte[] d = File.ReadAllBytes(path);
            int channels = 1, bits = 16, rate = 0;
            int pos = 12, dataOff = -1, dataLen = 0;
            while (pos + 8 <= d.Length)
            {
                string id = Encoding.ASCII.GetString(d, pos, 4);
                int len = BitConverter.ToInt32(d, pos + 4);
                if (id == "fmt " && pos + 24 <= d.Length)
                {
                    channels = BitConverter.ToInt16(d, pos + 10);
                    rate = BitConverter.ToInt32(d, pos + 12);
                    bits = BitConverter.ToInt16(d, pos + 22);
                }
                else if (id == "data")
                {
                    dataOff = pos + 8;
                    dataLen = Math.Min(len, d.Length - dataOff);
                    break;
                }
                if (len < 0) break;
                pos += 8 + len + (len & 1);
            }
            if (dataOff < 0 || dataLen <= 0) return new double[] { -120, -120, 0 };
            double peak = 0, sum = 0;
            long count = 0;
            if (bits == 16)
            {
                for (int i = dataOff; i + 1 < dataOff + dataLen; i += 2)
                {
                    double v = BitConverter.ToInt16(d, i) / 32768.0;
                    peak = Math.Max(peak, Math.Abs(v));
                    sum += v * v;
                    count++;
                }
            }
            else
            {
                for (int i = dataOff; i < dataOff + dataLen; i++)
                {
                    double v = (d[i] - 128) / 128.0;
                    peak = Math.Max(peak, Math.Abs(v));
                    sum += v * v;
                    count++;
                }
            }
            double rms = count > 0 ? Math.Sqrt(sum / count) : 0;
            double seconds = (rate > 0 && channels > 0) ? (double)count / channels / rate : 0;
            return new double[] { peak > 0 ? 20 * Math.Log10(peak) : -120, rms > 0 ? 20 * Math.Log10(rms) : -120, seconds };
        }
    }

    // ================================================================== Lautsprechertest
    public class SpeakerTestForm : TestFormBase
    {
        readonly CheckBox leftOk, rightOk, cleanOk;

        public SpeakerTestForm()
            : base("Lautsprechertest",
                "Spiele die Töne ab und höre genau hin. Ist nichts zu hören, erhöhe bitte selbst die Lautstärke mit den Lautstärketasten " +
                "(das Programm verändert keine Einstellungen). Achte auf Kratzen, Scheppern oder Aussetzer – besonders bei der Tonfolge.",
                760, 430, true)
        {
            FlowLayoutPanel p = new FlowLayoutPanel();
            p.Dock = DockStyle.Fill;
            p.FlowDirection = FlowDirection.TopDown;
            p.WrapContents = false;
            p.Padding = new Padding(10);
            FlowLayoutPanel row = new FlowLayoutPanel();
            row.AutoSize = true;
            row.WrapContents = false;
            row.Controls.Add(Ui.Btn("▶  Linker Lautsprecher", delegate { PlaySafe(AudioUtil.MakeWav(44100, 1.5, 440, 440, true, false, 0.6)); }));
            row.Controls.Add(Ui.Btn("▶  Rechter Lautsprecher", delegate { PlaySafe(AudioUtil.MakeWav(44100, 1.5, 660, 660, false, true, 0.6)); }));
            row.Controls.Add(Ui.Btn("▶  Tonfolge tief → hoch (beide)", delegate { PlaySafe(AudioUtil.MakeWav(44100, 4.0, 120, 6000, true, true, 0.5)); }));
            p.Controls.Add(row);
            leftOk = MakeCheck("Linker Ton war (nur) links deutlich zu hören");
            rightOk = MakeCheck("Rechter Ton war (nur) rechts deutlich zu hören");
            cleanOk = MakeCheck("Kein Kratzen, Scheppern, Rauschen oder Aussetzer");
            p.Controls.Add(leftOk);
            p.Controls.Add(rightOk);
            p.Controls.Add(cleanOk);
            Content.Controls.Add(p);
            FinishLayout();
        }

        static CheckBox MakeCheck(string text)
        {
            CheckBox c = new CheckBox();
            c.Text = text;
            c.AutoSize = true;
            c.Margin = new Padding(8, 8, 3, 3);
            return c;
        }

        void PlaySafe(byte[] wav)
        {
            try { Cursor = Cursors.WaitCursor; AudioUtil.Play(wav); }
            catch (Exception ex) { MessageBox.Show(this, "Wiedergabe fehlgeschlagen: " + ex.Message, "Lautsprechertest"); }
            finally { Cursor = Cursors.Default; }
        }

        protected override bool OnOkClicked()
        {
            if (leftOk.Checked && rightOk.Checked && cleanOk.Checked) return true;
            MessageBox.Show(this, "Bitte zuerst alle drei Punkte bestätigen – oder „Problem gefunden“ wählen.", "Lautsprechertest",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return false;
        }

        protected override bool OnProblemClicked()
        {
            if (!leftOk.Checked) Result.Problems.Add("Linker Lautsprecher nicht/kaum hörbar");
            if (!rightOk.Checked) Result.Problems.Add("Rechter Lautsprecher nicht/kaum hörbar");
            if (!cleanOk.Checked) Result.Problems.Add("Störgeräusche (Kratzen/Scheppern/Aussetzer)");
            if (Result.Problems.Count == 0) Result.Problems.Add("Problem laut Prüfer (siehe Anmerkung)");
            return true;
        }
    }

    // ================================================================== Mikrofontest
    public class MicTestForm : TestFormBase
    {
        readonly string wavPath;
        readonly Button recordBtn, playBtn;
        readonly Label levelLabel;
        readonly ProgressBar levelBar;
        readonly CheckBox voiceOk, noiseOk;
        readonly Timer timer;
        DateTime recordStart;
        bool recording;
        public double PeakDb = -120, RmsDb = -120;
        public string RecordError = "";

        public MicTestForm(string tempWavPath)
            : base("Mikrofontest",
                "Klicke auf „Aufnahme starten“ und sprich 5 Sekunden lang in normaler Lautstärke (z. B. zählen). " +
                "Danach „Abspielen“ und prüfen, ob deine Stimme klar zu hören ist. Die Aufnahme wird anschließend gelöscht.",
                760, 470, true)
        {
            wavPath = tempWavPath;
            FlowLayoutPanel p = new FlowLayoutPanel();
            p.Dock = DockStyle.Fill;
            p.FlowDirection = FlowDirection.TopDown;
            p.WrapContents = false;
            p.Padding = new Padding(10);
            FlowLayoutPanel row = new FlowLayoutPanel();
            row.AutoSize = true;
            row.WrapContents = false;
            recordBtn = Ui.Btn("●  Aufnahme starten (5 s)", OnRecord);
            playBtn = Ui.Btn("▶  Aufnahme abspielen", OnPlay);
            playBtn.Enabled = false;
            row.Controls.Add(recordBtn);
            row.Controls.Add(playBtn);
            p.Controls.Add(row);
            levelBar = new ProgressBar();
            levelBar.Width = 600;
            levelBar.Minimum = 0;
            levelBar.Maximum = 100;
            levelBar.Margin = new Padding(8, 10, 3, 3);
            p.Controls.Add(levelBar);
            levelLabel = new Label();
            levelLabel.AutoSize = true;
            levelLabel.MaximumSize = new Size(680, 0);
            levelLabel.Margin = new Padding(8, 6, 3, 3);
            levelLabel.Text = "Noch keine Aufnahme.";
            p.Controls.Add(levelLabel);
            voiceOk = new CheckBox();
            voiceOk.Text = "Meine Stimme ist in der Aufnahme deutlich zu hören";
            voiceOk.AutoSize = true;
            voiceOk.Margin = new Padding(8, 12, 3, 3);
            noiseOk = new CheckBox();
            noiseOk.Text = "Kein starkes Rauschen, Brummen oder Knacken";
            noiseOk.AutoSize = true;
            noiseOk.Margin = new Padding(8, 6, 3, 3);
            p.Controls.Add(voiceOk);
            p.Controls.Add(noiseOk);
            Content.Controls.Add(p);
            timer = new Timer();
            timer.Interval = 100;
            timer.Tick += OnTick;
            FormClosed += delegate
            {
                timer.Stop();
                if (recording) { try { AudioUtil.Mci("close bcrec"); } catch { } }
                try { if (File.Exists(wavPath)) File.Delete(wavPath); } catch { }
            };
            FinishLayout();
        }

        void OnRecord(object sender, EventArgs e)
        {
            try
            {
                try { AudioUtil.Mci("close bcrec"); } catch { }
                AudioUtil.Mci("open new type waveaudio alias bcrec");
                try { AudioUtil.Mci("set bcrec bitspersample 16 channels 1 samplespersec 22050 bytespersec 44100 alignment 2"); } catch { }
                AudioUtil.Mci("record bcrec");
                recording = true;
                recordStart = DateTime.Now;
                recordBtn.Enabled = false;
                playBtn.Enabled = false;
                levelLabel.Text = "Aufnahme läuft … bitte sprechen.";
                levelLabel.ForeColor = Color.Black;
                timer.Start();
            }
            catch (Exception ex)
            {
                RecordError = ex.Message;
                levelLabel.Text = "Aufnahme nicht möglich: " + ex.Message +
                    "\nMögliche Ursachen: kein Mikrofon erkannt oder Mikrofonzugriff für Desktop-Apps in den Windows-Datenschutzeinstellungen gesperrt.";
                levelLabel.ForeColor = Ui.Red;
            }
        }

        void OnTick(object sender, EventArgs e)
        {
            double s = (DateTime.Now - recordStart).TotalSeconds;
            levelBar.Value = Math.Min(100, (int)(s / 5.0 * 100));
            if (s < 5.0) return;
            timer.Stop();
            recording = false;
            try
            {
                AudioUtil.Mci("stop bcrec");
                AudioUtil.Mci("save bcrec \"" + wavPath + "\"");
                AudioUtil.Mci("close bcrec");
                double[] a = AudioUtil.AnalyzeWav(wavPath);
                PeakDb = a[0];
                RmsDb = a[1];
                int bar = (int)Math.Max(0, Math.Min(100, (PeakDb + 60) / 60 * 100));
                levelBar.Value = bar;
                string verdict;
                if (PeakDb < -55) { verdict = "Praktisch Stille – Mikrofon defekt, stummgeschaltet oder Zugriff gesperrt?"; levelLabel.ForeColor = Ui.Red; }
                else if (PeakDb < -35) { verdict = "Sehr leise – Mikrofon evtl. schwach oder weit entfernt."; levelLabel.ForeColor = Ui.Orange; }
                else if (PeakDb > -0.5) { verdict = "Übersteuert (sehr laut) – meist unkritisch."; levelLabel.ForeColor = Ui.Orange; }
                else { verdict = "Pegel in Ordnung."; levelLabel.ForeColor = Ui.Green; }
                levelLabel.Text = "Spitzenpegel " + PeakDb.ToString("0.0") + " dBFS, Mittel " + RmsDb.ToString("0.0") + " dBFS – " + verdict;
                playBtn.Enabled = true;
            }
            catch (Exception ex)
            {
                RecordError = ex.Message;
                levelLabel.Text = "Aufnahme fehlgeschlagen: " + ex.Message;
                levelLabel.ForeColor = Ui.Red;
            }
            recordBtn.Enabled = true;
        }

        void OnPlay(object sender, EventArgs e)
        {
            try
            {
                Cursor = Cursors.WaitCursor;
                using (SoundPlayer p = new SoundPlayer(wavPath)) { p.PlaySync(); }
            }
            catch (Exception ex) { MessageBox.Show(this, "Wiedergabe fehlgeschlagen: " + ex.Message, "Mikrofontest"); }
            finally { Cursor = Cursors.Default; }
        }

        protected override bool OnOkClicked()
        {
            if (voiceOk.Checked && noiseOk.Checked) return true;
            MessageBox.Show(this, "Bitte zuerst beide Punkte bestätigen – oder „Problem gefunden“ wählen.", "Mikrofontest",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return false;
        }

        protected override bool OnProblemClicked()
        {
            if (!voiceOk.Checked) Result.Problems.Add("Stimme nicht oder kaum hörbar");
            if (!noiseOk.Checked) Result.Problems.Add("Störgeräusche in der Aufnahme");
            if (Result.Problems.Count == 0) Result.Problems.Add("Problem laut Prüfer (siehe Anmerkung)");
            return true;
        }

        protected override void CollectDetails()
        {
            if (PeakDb > -120) Result.Details.Add("Aufnahmepegel: Spitze " + PeakDb.ToString("0.0") + " dBFS, Mittel " + RmsDb.ToString("0.0") + " dBFS");
            if (RecordError.Length > 0) Result.Details.Add("Aufnahmefehler: " + RecordError);
        }
    }

    // ================================================================== Externer Bildschirm
    public class ExternalDisplayForm : TestFormBase
    {
        readonly Label countLabel;
        readonly Timer timer;
        readonly int initialCount;
        int maxCount;
        readonly CheckBox imageOk, hdmi, usbc, other;

        public ExternalDisplayForm()
            : base("Bildausgang (HDMI / USB-C / DisplayPort)",
                "Schließe einen externen Monitor oder Fernseher an den Bildausgang an (HDMI, USB-C/Thunderbolt, DisplayPort). " +
                "Windows erkennt ihn normalerweise automatisch und zeigt dort ein Bild. Teste nach Möglichkeit jeden vorhandenen Ausgang.",
                760, 440, true)
        {
            initialCount = Screen.AllScreens.Length;
            maxCount = initialCount;
            FlowLayoutPanel p = new FlowLayoutPanel();
            p.Dock = DockStyle.Fill;
            p.FlowDirection = FlowDirection.TopDown;
            p.WrapContents = false;
            p.Padding = new Padding(10);
            countLabel = new Label();
            countLabel.AutoSize = true;
            countLabel.Font = Ui.BoldFont;
            countLabel.Margin = new Padding(8, 6, 3, 10);
            p.Controls.Add(countLabel);
            imageOk = Check("Bild erscheint auf dem externen Bildschirm");
            hdmi = Check("Getestet: HDMI");
            usbc = Check("Getestet: USB-C / Thunderbolt");
            other = Check("Getestet: DisplayPort / Mini-DP / VGA");
            p.Controls.Add(imageOk);
            p.Controls.Add(hdmi);
            p.Controls.Add(usbc);
            p.Controls.Add(other);
            Content.Controls.Add(p);
            timer = new Timer();
            timer.Interval = 1000;
            timer.Tick += delegate { Poll(); };
            Shown += delegate { Poll(); timer.Start(); };
            FormClosed += delegate { timer.Stop(); };
            FinishLayout();
        }

        static CheckBox Check(string text)
        {
            CheckBox c = new CheckBox();
            c.Text = text;
            c.AutoSize = true;
            c.Margin = new Padding(8, 6, 3, 3);
            return c;
        }

        void Poll()
        {
            int n = Screen.AllScreens.Length;
            maxCount = Math.Max(maxCount, n);
            countLabel.Text = "Aktive Bildschirme: " + n + " (zu Beginn: " + initialCount + ")" +
                (maxCount > initialCount ? "  ✔ externer Bildschirm erkannt" : "  – noch kein zusätzlicher Bildschirm erkannt");
            countLabel.ForeColor = maxCount > initialCount ? Ui.Green : Color.Black;
        }

        protected override void CollectDetails()
        {
            Result.Details.Add("Bildschirme zu Beginn: " + initialCount + ", maximal erkannt: " + maxCount);
            List<string> t = new List<string>();
            if (hdmi.Checked) t.Add("HDMI");
            if (usbc.Checked) t.Add("USB-C/Thunderbolt");
            if (other.Checked) t.Add("DisplayPort/Mini-DP/VGA");
            if (t.Count > 0) Result.Details.Add("Getestete Ausgänge: " + string.Join(", ", t.ToArray()));
            if (imageOk.Checked) Result.Details.Add("Bild auf externem Bildschirm bestätigt");
        }

        protected override bool OnOkClicked()
        {
            if (imageOk.Checked) return true;
            MessageBox.Show(this, "Bitte bestätigen, dass ein Bild erscheint – oder „Problem gefunden“ bzw. „Überspringen“ wählen.",
                "Bildausgang", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return false;
        }

        protected override bool OnProblemClicked()
        {
            if (maxCount <= initialCount) Result.Problems.Add("Externer Bildschirm wurde nicht erkannt");
            if (!imageOk.Checked) Result.Problems.Add("Kein Bild auf dem externen Bildschirm");
            if (Result.Problems.Count == 0) Result.Problems.Add("Problem laut Prüfer (siehe Anmerkung)");
            return true;
        }
    }

    // ================================================================== Warten auf Netzteil ein/aus
    public class PowerWaitDialog : Form
    {
        readonly bool wantOnline;
        readonly Label stateLabel;
        readonly Timer timer;

        public PowerWaitDialog(string title, string message, bool wantOnline)
        {
            this.wantOnline = wantOnline;
            Ui.Init(this, title, 600, 220);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            Label l = Ui.Wrap(message, 560, Ui.BaseFont, Color.Empty);
            l.Location = new Point(16, 16);
            stateLabel = new Label();
            stateLabel.AutoSize = true;
            stateLabel.Font = Ui.BoldFont;
            stateLabel.Location = new Point(16, 120);
            Button skip = Ui.Btn("Überspringen", delegate { DialogResult = DialogResult.Cancel; Close(); });
            skip.Location = new Point(470, 160);
            Controls.Add(l);
            Controls.Add(stateLabel);
            Controls.Add(skip);
            CancelButton = skip;
            timer = new Timer();
            timer.Interval = 500;
            timer.Tick += delegate { Poll(); };
            Shown += delegate { Poll(); timer.Start(); };
            FormClosed += delegate { timer.Stop(); };
            Load += delegate
            {
                stateLabel.Top = l.Bottom + 12;
                skip.Top = stateLabel.Bottom + 12;
                skip.Left = ClientSize.Width - skip.Width - 16;
                ClientSize = new Size(ClientSize.Width, skip.Bottom + 12);
            };
            ResumeLayout(false);
        }

        void Poll()
        {
            bool online = IsOnline();
            int pct = BatteryPercent();
            stateLabel.Text = "Aktuell: " + (online ? "Netzteil angeschlossen" : "Akkubetrieb") + (pct >= 0 ? ", Akku " + pct + " %" : "");
            if (online == wantOnline) { DialogResult = DialogResult.OK; Close(); }
        }

        public static bool IsOnline()
        {
            try { return SystemInformation.PowerStatus.PowerLineStatus == PowerLineStatus.Online; }
            catch { return true; }
        }

        public static int BatteryPercent()
        {
            try
            {
                float p = SystemInformation.PowerStatus.BatteryLifePercent;
                if (p < 0 || p > 1.0f) return -1;
                return (int)Math.Round(p * 100);
            }
            catch { return -1; }
        }

        // true = Zustand erreicht, false = übersprungen
        public static bool WaitFor(string title, string message, bool wantOnline)
        {
            if (IsOnline() == wantOnline) return true;
            using (PowerWaitDialog d = new PowerWaitDialog(title, message, wantOnline)) { return d.ShowDialog() == DialogResult.OK; }
        }
    }

    // ================================================================== Checkliste (Sichtprüfung)
    public class ChecklistItem
    {
        public string Text = "";
        public string Hint = "";
        public int State = 2;     // 0 = OK, 1 = Problem, 2 = nicht geprüft
        public string Comment = "";
        public ChecklistItem() { }
        public ChecklistItem(string text, string hint) { Text = text; Hint = hint ?? ""; }
    }

    public class ChecklistDialog : Form
    {
        readonly ChecklistItem[] items;
        readonly List<RadioButton[]> radios = new List<RadioButton[]>();
        readonly List<TextBox> comments = new List<TextBox>();

        public ChecklistDialog(string title, string intro, ChecklistItem[] items)
        {
            this.items = items;
            Ui.Init(this, title, 1080, 720);
            MinimumSize = new Size(820, 500);

            Label introLabel = new Label();
            introLabel.Text = intro ?? "";
            introLabel.Dock = DockStyle.Top;
            introLabel.Padding = new Padding(14, 10, 14, 6);
            introLabel.BackColor = Ui.PanelGray;

            Panel scroll = new Panel();
            scroll.Dock = DockStyle.Fill;
            scroll.AutoScroll = true;

            TableLayoutPanel t = new TableLayoutPanel();
            t.ColumnCount = 3;
            t.AutoSize = true;
            t.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            t.Location = new Point(8, 8);
            t.CellBorderStyle = TableLayoutPanelCellBorderStyle.Single;
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 470));
            t.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 270));
            foreach (ChecklistItem it in items)
            {
                Label l = new Label();
                l.Text = it.Text + (it.Hint.Length > 0 ? "\n" + it.Hint : "");
                l.AutoSize = true;
                l.MaximumSize = new Size(460, 0);
                l.Margin = new Padding(6);
                FlowLayoutPanel rp = new FlowLayoutPanel();
                rp.AutoSize = true;
                rp.WrapContents = false;
                rp.Margin = new Padding(4);
                RadioButton ok = new RadioButton(); ok.Text = "OK"; ok.AutoSize = true;
                RadioButton bad = new RadioButton(); bad.Text = "Problem"; bad.AutoSize = true; bad.ForeColor = Ui.Red;
                RadioButton na = new RadioButton(); na.Text = "nicht geprüft"; na.AutoSize = true; na.ForeColor = Ui.Gray;
                if (it.State == 0) ok.Checked = true; else if (it.State == 1) bad.Checked = true; else na.Checked = true;
                rp.Controls.Add(ok);
                rp.Controls.Add(bad);
                rp.Controls.Add(na);
                TextBox c = new TextBox();
                c.Width = 255;
                c.Margin = new Padding(6);
                c.Text = it.Comment;
                radios.Add(new RadioButton[] { ok, bad, na });
                comments.Add(c);
                t.Controls.Add(l);
                t.Controls.Add(rp);
                t.Controls.Add(c);
            }
            scroll.Controls.Add(t);

            FlowLayoutPanel bottom = new FlowLayoutPanel();
            bottom.Dock = DockStyle.Bottom;
            bottom.AutoSize = true;
            bottom.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bottom.FlowDirection = FlowDirection.RightToLeft;
            bottom.WrapContents = false;
            bottom.Padding = new Padding(10, 6, 10, 6);
            bottom.BackColor = Ui.PanelGray;
            Button done = Ui.Btn("Fertig", delegate { DialogResult = DialogResult.OK; Close(); });
            done.Font = Ui.BoldFont;
            bottom.Controls.Add(done);

            Controls.Add(scroll);
            Controls.Add(bottom);
            Controls.Add(introLabel);
            Resize += delegate { Ui.FitHeight(introLabel, ClientSize.Width); };
            Load += delegate { Ui.FitHeight(introLabel, ClientSize.Width); };
            FormClosing += delegate { Collect(); };
            ResumeLayout(false);
            PerformLayout();
        }

        void Collect()
        {
            for (int i = 0; i < items.Length; i++)
            {
                RadioButton[] r = radios[i];
                items[i].State = r[0].Checked ? 0 : (r[1].Checked ? 1 : 2);
                items[i].Comment = comments[i].Text.Trim();
            }
        }
    }
}
