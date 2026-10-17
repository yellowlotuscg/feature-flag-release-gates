using Azure.Identity;
using Microsoft.FeatureManagement;
using Microsoft.FeatureManagement.FeatureFilters;

var builder = WebApplication.CreateBuilder(args);

var appConfigEndpoint = builder.Configuration["AzureAppConfigurationEndpoint"]
    ?? Environment.GetEnvironmentVariable("AZURE_APPCONFIG_ENDPOINT");
if (!string.IsNullOrWhiteSpace(appConfigEndpoint))
{
    builder.Configuration.AddAzureAppConfiguration(options =>
    {
        options.Connect(new Uri(appConfigEndpoint), new DefaultAzureCredential())
            .UseFeatureFlags()
            .ConfigureRefresh(refresh => refresh.RegisterAll());
    });
    builder.Services.AddAzureAppConfiguration();
}

builder.Services.AddFeatureManagement()
    .AddFeatureFilter<ContextualTargetingFilter>();
builder.Services.AddSingleton<PricingCatalog>();

var app = builder.Build();
if (!string.IsNullOrWhiteSpace(appConfigEndpoint))
{
    app.UseAzureAppConfiguration();
}

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapGet("/features", async (
    HttpRequest request,
    IFeatureManagerSnapshot features,
    CancellationToken cancellationToken) =>
{
    var context = BuildTargetingContext(request, null);
    return Results.Ok(new
    {
        VolumeDiscounts = await features.IsEnabledAsync("VolumeDiscounts", context),
        RegionalTax = await features.IsEnabledAsync("RegionalTax", context),
        KillSwitch = await features.IsEnabledAsync("KillSwitch", context)
    });
});

app.MapPost("/quote", async (
    QuoteRequest request,
    HttpRequest httpRequest,
    IFeatureManagerSnapshot features,
    PricingCatalog catalog,
    IConfiguration configuration,
    CancellationToken cancellationToken) =>
{
    var product = catalog.Find(request.ProductId);
    if (product is null)
    {
        return Results.NotFound(new { error = $"Unknown product '{request.ProductId}'." });
    }

    if (request.Quantity < 1 || request.Quantity > 100_000)
    {
        return Results.BadRequest(new { error = "Quantity must be between 1 and 100000." });
    }

    var targetingContext = BuildTargetingContext(httpRequest, request);
    var killSwitch = await features.IsEnabledAsync("KillSwitch");
    var discountsEnabled = !killSwitch && await features.IsEnabledAsync("VolumeDiscounts", targetingContext);
    var taxEnabled = !killSwitch && await features.IsEnabledAsync("RegionalTax", targetingContext);

    var baseTotal = decimal.Round(product.UnitPrice * request.Quantity, 2, MidpointRounding.AwayFromZero);
    var discountPercent = discountsEnabled
        ? configuration.GetValue<decimal>("Pricing:DiscountPercent", 10)
        : 0;
    var discount = decimal.Round(baseTotal * discountPercent / 100m, 2, MidpointRounding.AwayFromZero);
    var subtotal = baseTotal - discount;
    var taxRate = taxEnabled
        ? configuration.GetValue<decimal>($"Pricing:TaxRates:{request.Region.ToUpperInvariant()}",
            configuration.GetValue<decimal>("Pricing:TaxRates:DEFAULT", 0))
        : 0;
    var tax = decimal.Round(subtotal * taxRate, 2, MidpointRounding.AwayFromZero);
    var total = subtotal + tax;

    return Results.Ok(new QuoteResponse(
        product.Sku,
        product.Name,
        request.Quantity,
        product.UnitPrice,
        baseTotal,
        discount,
        tax,
        total,
        discountsEnabled,
        taxEnabled,
        killSwitch,
        request.Region.ToUpperInvariant()));
});

app.Run();

static TargetingContext BuildTargetingContext(HttpRequest httpRequest, QuoteRequest? request)
{
    var userId = request?.UserId
        ?? httpRequest.Headers["X-User-Id"].FirstOrDefault()
        ?? httpRequest.Query["userId"].FirstOrDefault()
        ?? "anonymous";
    var groupText = httpRequest.Headers["X-User-Groups"].FirstOrDefault()
        ?? httpRequest.Query["groups"].FirstOrDefault()
        ?? string.Empty;
    var groups = request?.Groups?.ToArray()
        ?? groupText.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    return new TargetingContext
    {
        UserId = userId,
        Groups = groups
    };
}

public sealed record QuoteRequest(
    string ProductId,
    int Quantity,
    string Region = "DEFAULT",
    string? UserId = null,
    IReadOnlyList<string>? Groups = null);

public sealed record QuoteResponse(
    string ProductId,
    string ProductName,
    int Quantity,
    decimal UnitPrice,
    decimal BaseTotal,
    decimal Discount,
    decimal Tax,
    decimal Total,
    bool VolumeDiscountsEnabled,
    bool RegionalTaxEnabled,
    bool KillSwitch,
    string Region);

public sealed record Product(string Sku, string Name, decimal UnitPrice);

public sealed class PricingCatalog
{
    private static readonly IReadOnlyDictionary<string, Product> Products =
        new Dictionary<string, Product>(StringComparer.OrdinalIgnoreCase)
        {
            ["NW-ALPHA"] = new("NW-ALPHA", "Northwind Widget Alpha", 19.99m),
            ["NW-BETA"] = new("NW-BETA", "Northwind Widget Beta", 29.50m),
            ["NW-GAMMA"] = new("NW-GAMMA", "Northwind Widget Gamma", 49.00m)
        };

    public Product? Find(string productId) =>
        Products.TryGetValue(productId, out var product) ? product : null;
}

public partial class Program;
