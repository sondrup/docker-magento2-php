#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

travisEnv=
for version in "${versions[@]}"; do

	dockerfiles=()

	for suite in stretch jessie alpine3.6 alpine3.4; do
		[ -d "$version/$suite" ] || continue
		alpineVer="${suite#alpine}"

		baseDockerfile=Dockerfile-debian.template
		if [ "${suite#alpine}" != "$suite" ]; then
			baseDockerfile=Dockerfile-alpine.template
		fi

		for variant in cli apache fpm zts; do
			[ -d "$version/$suite/$variant" ] || continue
			{ generated_warning; cat "$baseDockerfile"; } > "$version/$suite/$variant/Dockerfile"
			if [ -f "$variant-Dockerfile-block-1" ]; then
				echo "Generating $version/$suite/$variant/Dockerfile from $baseDockerfile + $variant-Dockerfile-block-*"
				gawk -i inplace '
					$1 == "##</autogenerated>##" { ia = 0 }
					!ia { print }
					$1 == "##<autogenerated>##" { ia = 1; ab++; ac = 0 }
					ia { ac++ }
					ia && ac == 1 { system("cat '$variant'-Dockerfile-block-" ab) }
				' "$version/$suite/$variant/Dockerfile"
			fi

			sed -ri \
				-e 's!%%PHP_SUITE%%!'"$version-$variant-$suite"'!' \
				"$version/$suite/$variant/Dockerfile"
			dockerfiles+=( "$version/$suite/$variant/Dockerfile" )
		done
	done

	newTravisEnv=
	for dockerfile in "${dockerfiles[@]}"; do
		dir="${dockerfile%Dockerfile}"
		dir="${dir%/}"
		variant="${dir#$version}"
		variant="${variant#/}"
		newTravisEnv+='\n  - VERSION='"$version VARIANT=$variant"
	done
	travisEnv="$newTravisEnv$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
