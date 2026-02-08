// Consts.cs - Standalone shim for building System.Drawing outside the mono tree
// Based on mono/mcs/build/common/Consts.cs.in

static partial class Consts
{
	public const string MonoCorlibVersion = "1A5E0066-58DC-428A-B21C-0AD6CDAE2789";
}

static partial class Consts
{
	public const string MonoVersion = "6.13.0";
	public const string MonoCompany = "Mono development team";
	public const string MonoProduct = "Mono Common Language Infrastructure";
	public const string MonoCopyright = "(c) Various Mono authors";

	public const string FxVersion = "4.0.0.0";
	public const string FxFileVersion = "4.6.57.0";
	public const string EnvironmentVersion = "4.0.30319.42000";

	public const string VsVersion = "0.0.0.0";
	public const string VsFileVersion = "11.0.0.0";

	const string PublicKeyToken = "7cec85d7bea7798e";

	public const string AssemblyI18N = "I18N, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=0738eb9f132ed756";
	public const string AssemblyMicrosoft_JScript = "Microsoft.JScript, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblyMicrosoft_VisualStudio = "Microsoft.VisualStudio, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblyMicrosoft_VisualStudio_Web = "Microsoft.VisualStudio.Web, Version=" + VsVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblyMicrosoft_VSDesigner = "Microsoft.VSDesigner, Version=" + VsVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblyMono_Http = "Mono.Http, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=0738eb9f132ed756";
	public const string AssemblyMono_Posix = "Mono.Posix, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=0738eb9f132ed756";
	public const string AssemblyMono_Security = "Mono.Security, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=0738eb9f132ed756";
	public const string AssemblyMono_Messaging_RabbitMQ = "Mono.Messaging.RabbitMQ, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=0738eb9f132ed756";
	public const string AssemblyCorlib = "mscorlib, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=" + PublicKeyToken;
	public const string AssemblySystem = "System, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=" + PublicKeyToken;
	public const string AssemblySystem_Data = "System.Data, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b77a5c561934e089";
	public const string AssemblySystem_Design = "System.Design, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblySystem_DirectoryServices = "System.DirectoryServices, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblySystem_Drawing = "System.Drawing, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblySystem_Drawing_Design = "System.Drawing.Design, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblySystem_Messaging = "System.Messaging, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblySystem_Security = "System.Security, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblySystem_ServiceProcess = "System.ServiceProcess, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblySystem_Web = "System.Web, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
	public const string AssemblySystem_Windows_Forms = "System.Windows.Forms, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=b77a5c561934e089";
	public const string AssemblySystem_2_0 = "System, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089";
	public const string AssemblySystemCore_3_5 = "System.Core, Version=3.5.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089";
	public const string AssemblySystem_Core = "System.Core, Version=" + FxVersion + ", Culture=neutral, PublicKeyToken=" + PublicKeyToken;
	public const string WindowsBase_3_0 = "WindowsBase, Version=3.0.0.0, PublicKeyToken=31bf3856ad364e35";
	public const string AssemblyWindowsBase = "WindowsBase, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35";
	public const string AssemblyPresentationCore_3_5 = "PresentationCore, Version=3.5.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35";
	public const string AssemblyPresentationCore_4_0 = "PresentationCore, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35";
	public const string AssemblyPresentationFramework_3_5 = "PresentationFramework, Version=3.5.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35";
	public const string AssemblySystemServiceModel_3_0 = "System.ServiceModel, Version=3.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089";
}
