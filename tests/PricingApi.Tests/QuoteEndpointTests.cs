using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Configuration.Memory;
using Microsoft.Extensions.Hosting;

using Xunit;

namespace PricingApi.Tests;

public sealed class PricingApiFactory : WebApplicationFactory<Program>
{
    public MutableMemoryProvider Flags { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Test");
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.Add(new MutableMemorySource(Flags));
        });
    }
}

public sealed class MutableMemorySource : IConfigurationSource
{
    private readonly MutableMemoryProvider _provider;

    public MutableMemorySource(MutableMemoryProvider provider) => _provider = provider;

    public IConfigurationProvider Build(IConfigurationBuilder builder) => _provider;
}

public sealed class MutableMemoryProvider : MemoryConfigurationProvider
{
    public MutableMemoryProvider() : base(new MemoryConfigurationSource()) { }

    public void SetAndReload(string key, string value)
    {
        Set(key, value);
        OnReload();
    }

    public void RemoveAndReload(string key)
    {
        Data.Remove(key);
        OnReload();
    }
}

public sealed class QuoteEndpointTests : IClassFixture<PricingApiFactory>
{
    private readonly PricingApiFactory _factory;

    public QuoteEndpointTests(PricingApiFactory factory)
    {
        _factory = factory;
        SetFlags(volume: "false", tax: "false", kill: "false");
    }

    private void SetFlags(string volume, string tax, string kill) 
    {
        _factory.Flags.SetAndReload("FeatureManagement:VolumeDiscounts", volume);
        _factory.Flags.SetAndReload("FeatureManagement:RegionalTax", tax);
        _factory.Flags.SetAndReload("FeatureManagement:KillSwitch", kill);
    }

    [Fact]
    public async Task Flags_off_return_base_pricing()
    {
        using var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync("/quote", new { productId = "NW-ALPHA", quantity = 10, region = "US" });
        var quote = await response.Content.ReadFromJsonAsync<Quote>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.NotNull(quote);
        Assert.Equal(199.90m, quote!.BaseTotal);
        Assert.Equal(0m, quote.Discount);
        Assert.Equal(0m, quote.Tax);
        Assert.Equal(199.90m, quote.Total);
    }

    [Fact]
    public async Task Volume_discount_flag_applies_discount()
    {
        SetFlags("true", "false", "false");
        using var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync("/quote", new { productId = "NW-ALPHA", quantity = 10 });
        var quote = await response.Content.ReadFromJsonAsync<Quote>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.NotNull(quote);
        Assert.Equal(19.99m, quote!.Discount);
        Assert.Equal(179.91m, quote.Total);
        Assert.True(quote.VolumeDiscountsEnabled);
    }

    [Fact]
    public async Task Percentage_rollout_is_deterministic_for_a_user()
    {
        _factory.Flags.RemoveAndReload("FeatureManagement:VolumeDiscounts");
        _factory.Flags.SetAndReload("FeatureManagement:RegionalTax", "false");
        _factory.Flags.SetAndReload("FeatureManagement:KillSwitch", "false");
        using var client = _factory.CreateClient();
        var outcomes = new Dictionary<string, bool>();
        for (var i = 0; i < 200; i++)
        {
            var user = $"customer-{i}";
            var request = new { productId = "NW-ALPHA", quantity = 10, userId = user };
            var first = await client.PostAsJsonAsync("/quote", request);
            var firstQuote = await first.Content.ReadFromJsonAsync<Quote>();
            var second = await client.PostAsJsonAsync("/quote", request);
            var secondQuote = await second.Content.ReadFromJsonAsync<Quote>();
            Assert.Equal(firstQuote!.VolumeDiscountsEnabled, secondQuote!.VolumeDiscountsEnabled);
            outcomes[user] = firstQuote.VolumeDiscountsEnabled;
        }

        Assert.Contains(true, outcomes.Values);
        Assert.Contains(false, outcomes.Values);
    }

    [Fact]
    public async Task Kill_switch_disables_features_after_configuration_reload()
    {
        SetFlags("true", "true", "false");
        using var client = _factory.CreateClient();
        var before = await client.PostAsJsonAsync("/quote", new { productId = "NW-BETA", quantity = 10, region = "US" });
        var enabledQuote = await before.Content.ReadFromJsonAsync<Quote>();
        Assert.Equal(287.40m, enabledQuote!.Total);

        _factory.Flags.SetAndReload("FeatureManagement:KillSwitch", "true");
        var after = await client.PostAsJsonAsync("/quote", new { productId = "NW-BETA", quantity = 10, region = "US" });
        var disabledQuote = await after.Content.ReadFromJsonAsync<Quote>();
        Assert.Equal(295m, disabledQuote!.Total);
        Assert.True(disabledQuote.KillSwitch);
        Assert.False(disabledQuote.VolumeDiscountsEnabled);
        Assert.False(disabledQuote.RegionalTaxEnabled);
    }

    [Fact]
    public async Task Quote_math_applies_discount_then_regional_tax()
    {
        SetFlags("true", "true", "false");
        using var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync("/quote", new { productId = "NW-GAMMA", quantity = 10, region = "US" });
        var quote = await response.Content.ReadFromJsonAsync<Quote>();

        Assert.NotNull(quote);
        Assert.Equal(490m, quote!.BaseTotal);
        Assert.Equal(49m, quote.Discount);
        Assert.Equal(36.38m, quote.Tax);
        Assert.Equal(477.38m, quote.Total);
    }

    private sealed record Quote(
        decimal BaseTotal,
        decimal Discount,
        decimal Tax,
        decimal Total,
        bool VolumeDiscountsEnabled,
        bool RegionalTaxEnabled,
        bool KillSwitch);
}
