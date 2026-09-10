# The API, built and published in one image and run from another. The build
# stage carries the SDK, the compilers and the whole NuGet cache; none of that
# is any use at runtime and all of it would be surface area on a public host.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Project files first, restored on their own. This layer is cached until a
# dependency actually changes, so editing a .cs file does not re-download the
# package graph on every deploy.
COPY src/ICanRead.Domain/ICanRead.Domain.csproj src/ICanRead.Domain/
COPY src/ICanRead.Application/ICanRead.Application.csproj src/ICanRead.Application/
COPY src/ICanRead.Infrastructure/ICanRead.Infrastructure.csproj src/ICanRead.Infrastructure/
COPY src/ICanRead.Api/ICanRead.Api.csproj src/ICanRead.Api/
RUN dotnet restore src/ICanRead.Api/ICanRead.Api.csproj

COPY src/ ./src/
RUN dotnet publish src/ICanRead.Api/ICanRead.Api.csproj \
    --configuration Release \
    --no-restore \
    --output /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app ./

# The base image ships this user. Running as root inside a container that faces
# the internet buys nothing: the app writes no files and installs nothing.
USER $APP_UID

# Not a hardcoded port — the host tells us which one to answer on through PORT
# and Program.cs binds it. This is the fallback for running the image by hand,
# and matches the default Render assigns.
ENV ASPNETCORE_HTTP_PORTS=10000
EXPOSE 10000

ENTRYPOINT ["dotnet", "ICanRead.Api.dll"]
