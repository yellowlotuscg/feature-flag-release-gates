# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY src/PricingApi/PricingApi.csproj src/PricingApi/
RUN dotnet restore src/PricingApi/PricingApi.csproj
COPY src/PricingApi/ src/PricingApi/
RUN dotnet publish src/PricingApi/PricingApi.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
RUN addgroup --system --gid 10001 appgroup && adduser --system --uid 10001 --ingroup appgroup appuser
COPY --from=build /app/publish .
USER appuser
ENTRYPOINT ["dotnet", "PricingApi.dll"]
